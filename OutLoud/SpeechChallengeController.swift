import AVFoundation
import Foundation
import OSLog
import Speech
import UIKit

enum SpeechCaptureEvent {
    case transcript(String, isFinal: Bool)
    case level(CGFloat)
    case failure(Error)
}

@MainActor
protocol SpeechCapture: AnyObject {
    func requestPermissions(_ completion: @escaping (Bool) -> Void)
    func start(phrases: [String], receive: @escaping (SpeechCaptureEvent) -> Void) throws
    func finish()
    func stop()
}

@MainActor
final class SpeechChallengeController: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published private(set) var lastRejectedTranscript: String?
    @Published var isListening = false
    @Published var isFinalizing = false
    @Published var isRecovering = false
    @Published var statusMessage: String?
    @Published var audioLevel: CGFloat = 0
    @Published var errorMessage: String?
    @Published private(set) var errorTitle = "Couldn’t listen"

    private let classify: (String) async -> AcknowledgementMatch
    private var classificationTask: Task<Void, Never>?
    private let capture: SpeechCapture
    private let now: () -> Date
    private let classificationTimeout: UInt64
    private let finalizationTimeout: UInt64
    private let recoveryDelay: UInt64
    private let isApplicationActive: @MainActor () -> Bool
    private var timeoutTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveriesRemaining = 0
    private var rejectionCount = 0
    private var sessionID = UUID()
    private var lastVoiceAt: Date?
    private var currentExpectedPhrases: [String] = []
    private var currentAcceptsSimilar = false
    private var currentOnMatch: (() -> Void)?

    init(
        capture: SpeechCapture? = nil,
        classify: ((String) async -> AcknowledgementMatch)? = nil,
        now: @escaping () -> Date = Date.init,
        finalizationTimeout: UInt64 = 8_000_000_000,
        classificationTimeout: UInt64 = 15_000_000_000,
        recoveryDelay: UInt64 = 600_000_000,
        isApplicationActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }
    ) {
#if DEBUG && targetEnvironment(simulator)
        self.capture = capture ?? UITestScenario.makeSpeechCapture() ?? SystemSpeechCapture()
        self.classify = classify ?? UITestScenario.makeClassifier() ?? { await FlexibleAcknowledgementMatcher.evaluate(transcript: $0) }
#else
        self.capture = capture ?? SystemSpeechCapture()
        self.classify = classify ?? { await FlexibleAcknowledgementMatcher.evaluate(transcript: $0) }
#endif
        self.now = now
        self.finalizationTimeout = finalizationTimeout
        self.classificationTimeout = classificationTimeout
        self.recoveryDelay = recoveryDelay
        self.isApplicationActive = isApplicationActive
        super.init()
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        notifications.addObserver(self, selector: #selector(mediaServicesReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        notifications.addObserver(self, selector: #selector(mediaServicesReset), name: AVAudioSession.mediaServicesWereLostNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func audioInterrupted(_ notification: Notification) {
        guard isListening || isFinalizing || isRecovering,
              let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              type == AVAudioSession.InterruptionType.began.rawValue else { return }
        OutLoudLog.speech.info("Audio session interrupted; waiting for user retry")
        fail(SpeechCaptureError.audioInterrupted.localizedDescription)
    }

    @objc private func mediaServicesReset() {
        guard isListening || isFinalizing || isRecovering else { return }
        // Also cancel a pending reconnect: resets need a user-initiated restart.
        OutLoudLog.speech.info("Audio services unavailable/reset; waiting for user retry")
        fail(SpeechCaptureError.mediaServicesReset.localizedDescription)
    }

    func requestAndStart(
        expectedPhrases: [String],
        acceptsSimilarAcknowledgements: Bool,
        onMatch: @escaping () -> Void
    ) {
        stop()
        let sessionID = self.sessionID
        currentExpectedPhrases = expectedPhrases
        currentAcceptsSimilar = acceptsSimilarAcknowledgements
        currentOnMatch = onMatch
        transcript = ""
        lastRejectedTranscript = nil
        errorMessage = nil
        errorTitle = "Couldn’t listen"
        recoveriesRemaining = 1
        rejectionCount = 0
        capture.requestPermissions { [weak self] allowed in
            guard let self, self.sessionID == sessionID else { return }
            guard allowed else {
                self.errorMessage = "Microphone and Speech Recognition access are required. You can enable them in Settings."
                return
            }
            self.startCapture(expectedPhrases: expectedPhrases,
                              acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements, onMatch: onMatch)
        }
    }

    private func startCapture(expectedPhrases: [String], acceptsSimilarAcknowledgements: Bool, onMatch: @escaping () -> Void) {
        let sessionID = self.sessionID
        do {
            isRecovering = false
            isListening = true
            OutLoudLog.speech.info("Starting speech attempt \(sessionID.uuidString, privacy: .public)")
            try capture.start(phrases: acceptsSimilarAcknowledgements ? [] : expectedPhrases) { [weak self] event in
                guard let self, self.sessionID == sessionID else { return }
                self.receive(event, expectedPhrases: expectedPhrases,
                             acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements, onMatch: onMatch)
            }
        } catch {
            handleFailure(error, expectedPhrases: expectedPhrases,
                          acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements, onMatch: onMatch)
        }
    }

    func stop() {
        sessionID = UUID()
        classificationTask?.cancel()
        classificationTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        capture.stop()
        isListening = false
        isFinalizing = false
        isRecovering = false
        statusMessage = nil
        audioLevel = 0
        lastVoiceAt = nil
    }

    func pauseForBackground() {
        fail("Recording was paused. Return to OutLoud and tap Restart listening when you’re ready.")
    }

    /// End capture after a pause (or an explicit tap), then wait for the
    /// recognizer's final transcript. Partial matches never unlock an app.
    func finishSpeaking() {
        guard isListening, !isFinalizing else { return }
        isListening = false
        isFinalizing = true
        audioLevel = 0
        let sessionID = self.sessionID
        let expectedPhrases = self.currentExpectedPhrases
        let acceptsSimilar = self.currentAcceptsSimilar
        let onMatch = self.currentOnMatch
        timeoutTask = Task { [weak self, finalizationTimeout] in
            do { try await Task.sleep(nanoseconds: finalizationTimeout) }
            catch { return }
            guard let self, self.sessionID == sessionID, self.isFinalizing else { return }
            if !self.transcript.isEmpty, let onMatch {
                OutLoudLog.speech.info("Finalization timed out with partial transcript; evaluating available speech")
                self.processFinalTranscript(
                    self.transcript,
                    expectedPhrases: expectedPhrases,
                    acceptsSimilarAcknowledgements: acceptsSimilar,
                    onMatch: onMatch
                )
            } else {
                self.fail("Speech recognition took too long. Please try again.")
            }
        }
        capture.finish()
    }

    private func receive(
        _ event: SpeechCaptureEvent,
        expectedPhrases: [String],
        acceptsSimilarAcknowledgements: Bool,
        onMatch: @escaping () -> Void
    ) {
        guard isListening || isFinalizing else { return }
        switch event {
        case .level(let level):
            guard isListening else { return }
            audioLevel = (audioLevel * 0.62) + (level * 0.38)
            if level > 0.08 { lastVoiceAt = now() }
            if !transcript.isEmpty, let lastVoiceAt, now().timeIntervalSince(lastVoiceAt) >= 1.2 {
                finishSpeaking()
            }
        case .transcript(let text, let isFinal):
            transcript = text
            if lastVoiceAt == nil { lastVoiceAt = now() }
            guard isFinal else { return }
            processFinalTranscript(
                text,
                expectedPhrases: expectedPhrases,
                acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements,
                onMatch: onMatch
            )
        case .failure(let error):
            handleFailure(error, expectedPhrases: expectedPhrases,
                          acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements, onMatch: onMatch)
        }
    }

    private func processFinalTranscript(
        _ text: String,
        expectedPhrases: [String],
        acceptsSimilarAcknowledgements: Bool,
        onMatch: @escaping () -> Void
    ) {
        // Stop audio and invalidate all recognizer callbacks before inference.
        stop()
        if acceptsSimilarAcknowledgements {
            isFinalizing = true
            let checkingSession = sessionID
            timeoutTask = Task { [weak self, classificationTimeout] in
                do { try await Task.sleep(nanoseconds: classificationTimeout) }
                catch { return }
                guard let self, self.sessionID == checkingSession else { return }
                self.fail("Checking your words took too long. Please try again with a short acknowledgment.", title: "Couldn’t check your words")
            }
            classificationTask = Task { [weak self, classify] in
                let result = await classify(text)
                guard let self, !Task.isCancelled, self.sessionID == checkingSession else { return }
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.isFinalizing = false
                self.classificationTask = nil
                switch result {
                case .accepted:
                    self.lastRejectedTranscript = nil
                    OutLoudLog.speech.info("Final acknowledgement matched")
                    onMatch()
                case .rejected:
                    self.listenForNextPhrase(
                        expectedPhrases: expectedPhrases,
                        acceptsSimilarAcknowledgements: true,
                        message: "I couldn’t match that acknowledgment. Try again, or say a specific phrase instead.",
                        onMatch: onMatch)
                case .unavailable:
                    self.errorTitle = "Couldn’t check your words"
                    self.errorMessage = "Own words couldn’t load on this device. Please restart OutLoud and try again. You can also choose Specific phrases in Settings."
                }
            }
        } else if PhraseMatcher.matches(transcript: text, expectedPhrases: expectedPhrases) {
            lastRejectedTranscript = nil
            OutLoudLog.speech.info("Final spoken phrase matched")
            onMatch()
        } else {
            listenForNextPhrase(expectedPhrases: expectedPhrases,
                                acceptsSimilarAcknowledgements: false,
                                message: "Still listening. Say the full phrase again.", onMatch: onMatch)
        }
    }

    private func listenForNextPhrase(expectedPhrases: [String], acceptsSimilarAcknowledgements: Bool,
                                     message: String, onMatch: @escaping () -> Void) {
        // A mismatch is another turn in the same challenge. Each turn gets a
        // fresh transcript and session so old callbacks cannot accept or fail it.
        let rejectedTranscript = transcript
        stop()
        guard isApplicationActive() else {
            pauseForBackground()
            return
        }
        transcript = ""
        lastRejectedTranscript = rejectedTranscript
        rejectionCount += 1
        OutLoudLog.speech.info("Final phrase rejected; attempt \(self.rejectionCount, privacy: .public) of 3")
        guard rejectionCount < 3 else {
            fail(acceptsSimilarAcknowledgements
                 ? "I couldn’t match your words after three attempts. Check what I heard, then restart listening or say a specific phrase instead."
                 : "I couldn’t match the phrase after three attempts. Check what I heard, then restart listening and say the displayed phrase.",
                 title: "Couldn’t match your words")
            return
        }
        errorMessage = nil
        statusMessage = message
        recoveriesRemaining = 1
        startCapture(expectedPhrases: expectedPhrases,
                     acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements, onMatch: onMatch)
    }

    private func handleFailure(_ error: Error, expectedPhrases: [String],
                               acceptsSimilarAcknowledgements: Bool, onMatch: @escaping () -> Void) {
        let failure = error as NSError
        let phase = isFinalizing ? "finalizing" : "listening/startup"
        OutLoudLog.speech.error("Speech attempt \(self.sessionID.uuidString, privacy: .public) failed during \(phase, privacy: .public): \(failure.domain, privacy: .public) / \(failure.code, privacy: .public)")
        if failure.domain == "kAFAssistantErrorDomain" && failure.code == 201 {
            fail("Dictation is turned off. Turn on Enable Dictation in Settings > General > Keyboard, then try again.", title: "Dictation is turned off")
            return
        }
        let serviceInterrupted = failure.domain == "kAFAssistantErrorDomain" && [1101, 1107].contains(failure.code)
        if serviceInterrupted, recoveriesRemaining > 0, isApplicationActive() {
            recoveriesRemaining -= 1
            // Invalidate callbacks and discard partial speech before reconnecting.
            stop()
            transcript = ""
            isRecovering = true
            statusMessage = "Speech was interrupted. Please say the full phrase again when listening resumes."
            let sessionID = self.sessionID
            recoveryTask = Task { [weak self, recoveryDelay] in
                do { try await Task.sleep(nanoseconds: recoveryDelay) }
                catch { return }
                guard let self, self.sessionID == sessionID else { return }
                self.recoveryTask = nil
                guard self.isApplicationActive() else {
                    self.pauseForBackground()
                    return
                }
                self.startCapture(expectedPhrases: expectedPhrases,
                                  acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements, onMatch: onMatch)
            }
        } else if serviceInterrupted {
            fail("Speech recognition was interrupted. Tap Restart listening and say the full phrase. If this keeps happening, close and reopen OutLoud.")
        } else if let error = error as? SpeechCaptureError {
            fail(error.localizedDescription)
        } else {
            fail("I couldn’t hear the full phrase. Please try again.")
        }
    }

    private func fail(_ message: String, title: String = "Couldn’t listen") {
        stop()
        errorTitle = title
        errorMessage = message
    }
}

@MainActor
final class SystemSpeechCapture: SpeechCapture {
    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasAudioTap = false

    static let audioSessionCategoryOptions: AVAudioSession.CategoryOptions = [.duckOthers, .allowBluetooth]

    static func selectBestOnDeviceRecognizer(
        currentLocale: Locale = .current,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> SFSpeechRecognizer? {
        // 1. Current locale
        if let recognizer = SFSpeechRecognizer(locale: currentLocale),
           recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
            return recognizer
        }
        // 2. Preferred languages
        for lang in preferredLanguages {
            let locale = Locale(identifier: lang)
            if let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        // 3. Supported English locales
        let fallbackLocales = ["en-US", "en-GB", "en-CA", "en-AU", "en-IN", "en-NZ", "en-IE"]
        for id in fallbackLocales {
            let locale = Locale(identifier: id)
            if let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        // 4. Any supported locale
        for locale in SFSpeechRecognizer.supportedLocales() {
            if let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        // 5. Default
        if let recognizer = SFSpeechRecognizer(),
           recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
            return recognizer
        }
        return nil
    }

    func requestPermissions(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            AVAudioApplication.requestRecordPermission { allowed in
                Task { @MainActor in completion(status == .authorized && allowed) }
            }
        }
    }

    func start(phrases: [String], receive: @escaping (SpeechCaptureEvent) -> Void) throws {
        stop()
        // Never reuse an engine or recognizer from an interrupted attempt.
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        guard let recognizer = Self.selectBestOnDeviceRecognizer() else {
            throw SpeechCaptureError.unavailable
        }
        self.recognizer = recognizer
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: Self.audioSessionCategoryOptions)
        } catch {
            OutLoudLog.speech.notice("Measurement mode unavailable, falling back to default recording session: \(error.localizedDescription, privacy: .public)")
            do {
                try session.setCategory(.record, mode: .default, options: Self.audioSessionCategoryOptions)
            } catch {
                OutLoudLog.speech.notice("Category options unavailable, falling back to basic record: \(error.localizedDescription, privacy: .public)")
                try session.setCategory(.record, mode: .default)
            }
        }
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        request.contextualStrings = phrases.isEmpty
            ? [
                "bad choice", "wasting time", "procrastinating", "distracting me",
                "poor choice", "poor decision", "doomscrolling", "stop scrolling",
                "should be working", "get back to work"
              ]
            : Array(phrases.prefix(100))
        // Do not silently fall back to sending audio to a server.
        request.requiresOnDeviceRecognition = true
        self.request = request
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechCaptureError.microphoneUnavailable
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            let level = Self.normalizedAudioLevel(from: buffer)
            Task { @MainActor in receive(.level(level)) }
        }
        hasAudioTap = true
        audioEngine.prepare()
        try audioEngine.start()
        task = recognizer.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                if let result {
                    receive(.transcript(result.bestTranscription.formattedString, isFinal: result.isFinal))
                }
                if let error { receive(.failure(error)) }
            }
        }
    }

    func finish() {
        stopAudio()
        request?.endAudio()
    }

    func stop() {
        task?.cancel()
        task = nil
        stopAudio()
        request?.endAudio()
        request = nil
        audioEngine = nil
        recognizer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopAudio() {
        guard let audioEngine else { return }
        if audioEngine.isRunning { audioEngine.stop() }
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
    }

    private nonisolated static func normalizedAudioLevel(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frameCount { sum += channel[index] * channel[index] }
        let rms = sqrt(sum / Float(frameCount))
        guard rms > 0 else { return 0 }
        return CGFloat(max(0, min(1, (20 * log10(rms) + 50) / 45)))
    }
}

enum SpeechCaptureError: LocalizedError {
    case microphoneUnavailable, unavailable, audioInterrupted, mediaServicesReset
    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "No microphone input is available."
        case .unavailable: "On-device speech recognition is unavailable. Make sure Dictation is turned on in Settings > General > Keyboard and try again."
        case .audioInterrupted: "Recording was interrupted. Tap Try again when your microphone is available and say the full phrase."
        case .mediaServicesReset: "Your iPhone’s audio service restarted. Tap Try again and say the full phrase."
        }
    }
}
