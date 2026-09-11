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

/// Complete, explicit admissions have a deterministic meaning in the challenge
/// context. Never match a substring or discard a question, quotation, or clause.
enum ExplicitAcknowledgementMatcher {
    private static let acknowledgements: Set<String> = [
        "this is a bad choice",
        "i am making a bad choice",
        "i am wasting time",
        "i am wasting my time",
        "this is a waste of time",
        "i am procrastinating",
        "this is a poor choice",
        "i acknowledge this is a bad choice",
        "this app is distracting me",
        "i should be doing something else",
        "i should be working",
        "i should be working right now",
        "i need to get back to work",
        "i need to stop scrolling",
        "i am doomscrolling",
        "i am doomscrolling right now",
        "i realize this may not be wise",
        "bad choice",
        "wasting time",
        "poor choice",
        "poor decision",
        "distracting choice"
    ]

    static func matches(_ transcript: String) -> Bool {
        guard !transcript.contains("?") && !transcript.contains("？") else { return false }
        guard let text = AcknowledgementDecision.modelInput(transcript) else { return false }
        let statement = text.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!").union(.whitespacesAndNewlines))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return acknowledgements.contains(statement)
    }
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
        if ExplicitAcknowledgementMatcher.matches(transcript) { return .accepted }
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: evaluateOnQueue(transcript: transcript)) }
        }
    }

    // Synchronous entry point for routing/integration tests. Speech uses evaluate.
    static func matches(transcript: String) -> Bool {
        if ExplicitAcknowledgementMatcher.matches(transcript) { return true }
        return queue.sync { evaluateOnQueue(transcript: transcript) == .accepted }
    }

    private static func evaluateOnQueue(transcript: String) -> AcknowledgementMatch {
        guard !transcript.contains("?") && !transcript.contains("？") else { return .rejected }
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
