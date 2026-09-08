import AVFoundation
import Foundation
import OSLog
import Speech

enum SpeechCaptureEvent {
    case transcript(String, isFinal: Bool)
    case level(CGFloat)
    case failure(String)
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
    @Published var isListening = false
    @Published var isFinalizing = false
    @Published var audioLevel: CGFloat = 0
    @Published var errorMessage: String?

    private let capture: SpeechCapture
    private let now: () -> Date
    private let finalizationTimeout: UInt64
    private var timeoutTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var lastVoiceAt: Date?

    init(
        capture: SpeechCapture? = nil,
        now: @escaping () -> Date = Date.init,
        finalizationTimeout: UInt64 = 8_000_000_000
    ) {
#if DEBUG && targetEnvironment(simulator)
        self.capture = capture ?? UITestScenario.makeSpeechCapture() ?? SystemSpeechCapture()
#else
        self.capture = capture ?? SystemSpeechCapture()
#endif
        self.now = now
        self.finalizationTimeout = finalizationTimeout
        super.init()
    }

    func requestAndStart(
        expectedPhrases: [String],
        acceptsSimilarAcknowledgements: Bool,
        onMatch: @escaping () -> Void
    ) {
        stop()
        let sessionID = self.sessionID
        transcript = ""
        errorMessage = nil
        capture.requestPermissions { [weak self] allowed in
            guard let self, self.sessionID == sessionID else { return }
            guard allowed else {
                self.errorMessage = "Microphone and Speech Recognition access are required. You can enable them in Settings."
                return
            }
            do {
                self.isListening = true
                try self.capture.start(phrases: acceptsSimilarAcknowledgements ? [] : expectedPhrases) { [weak self] event in
                    guard let self, self.sessionID == sessionID else { return }
                    self.receive(event, expectedPhrases: expectedPhrases,
                                 acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements,
                                 onMatch: onMatch)
                }
            } catch {
                self.fail("Speech couldn’t start. \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        sessionID = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        capture.stop()
        isListening = false
        isFinalizing = false
        audioLevel = 0
        lastVoiceAt = nil
    }

    /// End capture after a pause (or an explicit tap), then wait for the
    /// recognizer's final transcript. Partial matches never unlock an app.
    func finishSpeaking() {
        guard isListening, !isFinalizing else { return }
        isListening = false
        isFinalizing = true
        audioLevel = 0
        let sessionID = self.sessionID
        timeoutTask = Task { [weak self, finalizationTimeout] in
            do { try await Task.sleep(nanoseconds: finalizationTimeout) }
            catch { return }
            guard let self, self.sessionID == sessionID, self.isFinalizing else { return }
            self.fail("Speech recognition took too long. Please try again.")
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
            if level > 0.18 { lastVoiceAt = now() }
            if !transcript.isEmpty, let lastVoiceAt, now().timeIntervalSince(lastVoiceAt) >= 1.2 {
                finishSpeaking()
            }
        case .transcript(let text, let isFinal):
            transcript = text
            if lastVoiceAt == nil { lastVoiceAt = now() }
            guard isFinal else { return }
            let matched = ChallengePhraseMatcher.matches(
                transcript: text, expectedPhrases: expectedPhrases,
                acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements
            )
            stop()
            if matched {
                OutLoudLog.speech.info("Final spoken phrase matched")
                onMatch()
            } else {
                errorMessage = "That didn’t match. Try saying the phrase again."
            }
        case .failure(let message):
            fail("I couldn’t hear the full phrase. \(message)")
        }
    }

    private func fail(_ message: String) {
        stop()
        errorMessage = message
    }
}

@MainActor
final class SystemSpeechCapture: SpeechCapture {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasAudioTap = false

    func requestPermissions(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            AVAudioApplication.requestRecordPermission { allowed in
                Task { @MainActor in completion(status == .authorized && allowed) }
            }
        }
    }

    func start(phrases: [String], receive: @escaping (SpeechCaptureEvent) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechCaptureError.unavailable
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        request.contextualStrings = Array(phrases.prefix(100))
        // Do not silently fall back to sending audio to a server.
        guard recognizer.supportsOnDeviceRecognition else { throw SpeechCaptureError.unavailable }
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
                if let error { receive(.failure(error.localizedDescription)) }
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopAudio() {
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

private enum SpeechCaptureError: LocalizedError {
    case microphoneUnavailable, unavailable
    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "No microphone input is available."
        case .unavailable: "On-device speech recognition is unavailable right now."
        }
    }
}
