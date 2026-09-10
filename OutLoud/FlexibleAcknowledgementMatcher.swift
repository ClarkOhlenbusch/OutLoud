import CoreML
import Foundation

enum ChallengePhraseMatcher {
    static func matches(
        transcript: String,
        expectedPhrases: [String],
        acceptsSimilarAcknowledgements: Bool
    ) -> Bool {
        if acceptsSimilarAcknowledgements {
            return FlexibleAcknowledgementMatcher.matches(transcript: transcript)
        }
        return PhraseMatcher.matches(transcript: transcript, expectedPhrases: expectedPhrases)
    }
}

enum AcknowledgementMatch: Equatable, Sendable {
    case accepted
    case rejected
    case unavailable
}

enum FlexibleAcknowledgementMatcher {
    // Serialize inference and loading off the UI thread. Use the same portable
    // CPU path as evaluation: accelerator rounding can affect borderline scores.
    private static let queue = DispatchQueue(label: "com.clarkohlenbusch.outloud.classification", qos: .userInitiated)

    // Access only on queue; loading and inference both stay off the UI thread.
    private static let loadedModel: AcknowledgementInference? = {
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            let coreModel = try FlexibleAcknowledgementClassifier(configuration: configuration).model
            guard let vocabularyURL = Bundle.main.url(forResource: "AcknowledgementVocabulary", withExtension: "txt") else { return nil }
            return try AcknowledgementInference(model: coreModel, vocabulary: Data(contentsOf: vocabularyURL))
        } catch {
            OutLoudLog.challenge.error("Flexible acknowledgement model failed to load")
            return nil
        }
    }()

    static var isModelAvailable: Bool { queue.sync { loadedModel != nil } }

    @discardableResult
    static func prepareModel() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: loadedModel != nil) }
        }
    }

    static func evaluate(transcript: String) async -> AcknowledgementMatch {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: evaluateOnQueue(transcript: transcript)) }
        }
    }

    // Synchronous entry point for routing/integration tests. Speech uses evaluate.
    static func matches(transcript: String) -> Bool {
        queue.sync { evaluateOnQueue(transcript: transcript) == .accepted }
    }

    private static func evaluateOnQueue(transcript: String) -> AcknowledgementMatch {
        guard AcknowledgementDecision.modelInput(transcript) != nil else { return .rejected }
        guard let loadedModel else { return .unavailable }
        do {
            return try loadedModel.matches(transcript: transcript) ? .accepted : .rejected
        } catch {
            OutLoudLog.challenge.error("Flexible acknowledgement inference failed")
            return .unavailable
        }
    }
}
