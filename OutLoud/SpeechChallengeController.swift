import AVFoundation
import Foundation
import OSLog
import Speech

@MainActor
final class SpeechChallengeController: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var audioLevel: CGFloat = 0
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasAudioTap = false

    func requestAndStart(expectedPhrase: String, onMatch: @escaping () -> Void) {
        OutLoudLog.speech.info("Preparing speech challenge")
        stop()
        transcript = ""
        errorMessage = nil

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            AVAudioApplication.requestRecordPermission { microphoneAllowed in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard speechStatus == .authorized, microphoneAllowed else {
                        OutLoudLog.speech.error(
                            "Speech permissions unavailable; speech status: \(speechStatus.rawValue, privacy: .public), microphone allowed: \(microphoneAllowed, privacy: .public)"
                        )
                        self.errorMessage = "Microphone and Speech Recognition access are required. You can enable them in Settings."
                        return
                    }
                    OutLoudLog.speech.info("Speech and microphone permissions are available")
                    self.start(expectedPhrase: expectedPhrase, onMatch: onMatch)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        isListening = false
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        OutLoudLog.speech.debug("Speech capture stopped")
    }

    private func start(expectedPhrase: String, onMatch: @escaping () -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            OutLoudLog.speech.error("Speech recognizer is unavailable")
            errorMessage = "Speech recognition is unavailable right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.contextualStrings = [expectedPhrase]
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                throw SpeechChallengeError.microphoneUnavailable
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)

                let level = Self.normalizedAudioLevel(from: buffer)
                Task { @MainActor [weak self] in
                    guard let self, self.isListening else { return }
                    self.audioLevel = (self.audioLevel * 0.62) + (level * 0.38)
                }
            }
            hasAudioTap = true

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            OutLoudLog.speech.info(
                "Speech capture started; on-device recognition: \(recognizer.supportsOnDeviceRecognition, privacy: .public)"
            )

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.transcript = text
                        if PhraseMatcher.matches(transcript: text, expected: expectedPhrase) {
                            OutLoudLog.speech.info("Spoken phrase matched")
                            self.stop()
                            onMatch()
                            return
                        }
                    }
                    if let error, self.isListening {
                        OutLoudLog.speech.error(
                            "Speech recognition failed: \(error.localizedDescription, privacy: .public)"
                        )
                        self.stop()
                        self.errorMessage = "I couldn’t hear the full phrase. \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            OutLoudLog.speech.error(
                "Microphone startup failed: \(error.localizedDescription, privacy: .public)"
            )
            stop()
            errorMessage = "The microphone couldn’t start. \(error.localizedDescription)"
        }
    }

    private nonisolated static func normalizedAudioLevel(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channel[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameCount))
        guard rms > 0 else { return 0 }

        // Map roughly -50...-5 dB into a smooth 0...1 visual range.
        let decibels = 20 * log10(rms)
        let normalized = max(0, min(1, (decibels + 50) / 45))
        return CGFloat(normalized)
    }
}

private enum SpeechChallengeError: LocalizedError {
    case microphoneUnavailable

    var errorDescription: String? {
        "No microphone input is available."
    }
}
