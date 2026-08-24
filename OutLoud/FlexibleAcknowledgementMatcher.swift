import CoreML
import Foundation
import NaturalLanguage

enum FlexibleAcknowledgementMatcher {
    private static let acknowledgementLabel = "acknowledges"
    private static let defaultThreshold = 0.88
    private static let contextualEmbedding = NLContextualEmbedding(language: .english)

    private struct LoadedModel {
        let model: NLModel
        let threshold: Double
    }

    private static let loadedModel: LoadedModel? = {
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let coreModel = try FlexibleAcknowledgementClassifier(configuration: configuration).model
            let naturalLanguageModel = try NLModel(mlModel: coreModel)
            let metadata = coreModel.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
            let threshold = metadata?["shippingThreshold"].flatMap(Double.init) ?? defaultThreshold
            return LoadedModel(model: naturalLanguageModel, threshold: threshold)
        } catch {
            OutLoudLog.challenge.error(
                "Flexible acknowledgement model failed to load: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }()

    static var isModelAvailable: Bool {
        loadedModel != nil
    }

    static var areModelAssetsAvailable: Bool {
        contextualEmbedding?.hasAvailableAssets == true
    }

    @discardableResult
    static func prepareModelAssets() async -> Bool {
        guard let contextualEmbedding else { return false }
        if contextualEmbedding.hasAvailableAssets {
            _ = loadedModel
            return true
        }

        do {
            let result = try await contextualEmbedding.requestAssets()
            let available = result == .available && contextualEmbedding.hasAvailableAssets
            OutLoudLog.challenge.info(
                "Flexible acknowledgement assets prepared; available: \(available, privacy: .public)"
            )
            if available { _ = loadedModel }
            return available
        } catch {
            OutLoudLog.challenge.error(
                "Flexible acknowledgement assets unavailable: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    static func matches(transcript: String) -> Bool {
        switch AcknowledgementPolicy.decision(for: transcript) {
        case .accept:
            return true
        case .reject:
            return false
        case .useModel:
            guard areModelAssetsAvailable, let loadedModel else { return false }
            let hypotheses = loadedModel.model.predictedLabelHypotheses(
                for: transcript,
                maximumCount: 2
            )
            return hypotheses[acknowledgementLabel, default: 0] >= loadedModel.threshold
        }
    }

}

private enum AcknowledgementPolicy {
    enum Decision {
        case accept
        case reject
        case useModel
    }

    private static let negativeJudgements: Set<String> = [
        "awful", "bad", "careless", "counterproductive", "dumb", "harmful", "impulsive",
        "irresponsible", "lousy", "pointless", "poor", "procrastinating", "regrettable",
        "sabotage", "stupid", "terrible", "trivial", "unhealthy", "unnecessary", "unwise",
        "waste", "wasting", "wrong"
    ]
    private static let decisionContext: Set<String> = [
        "app", "attention", "choice", "choosing", "decision", "distraction", "doing", "focus",
        "goals", "habit", "here", "impulse", "open", "opening", "priorities", "scroll",
        "scrolling", "this", "time", "urge", "use", "using"
    ]
    private static let modelCues: Set<String> = negativeJudgements.union([
        "abandon", "against", "avoid", "away", "better", "distracted", "elsewhere", "inconsistent",
        "need", "not", "procrastinate", "rather", "regret", "undermine", "wait"
    ])

    static func decision(for transcript: String) -> Decision {
        let normalized = PhraseMatcher.normalize(transcript)
        let words = Set(normalized.split(separator: " ").map(String.init))
        guard words.count >= 3 else { return .reject }
        guard !isQuestion(transcript, normalized: normalized),
              !isReportedOrHistorical(normalized),
              !expressesOppositeIntent(normalized) else {
            return .reject
        }

        if isExplicitAcknowledgement(normalized, words: words) {
            return .accept
        }

        let hasSpeakerContext = words.contains("i")
            || words.contains("me")
            || words.contains("my")
            || normalized.contains("this app")
            || normalized.contains("opening this")
            || normalized.contains("using this")
        guard hasSpeakerContext,
              !words.isDisjoint(with: decisionContext),
              !words.isDisjoint(with: modelCues) else {
            return .reject
        }
        return .useModel
    }

    private static func isExplicitAcknowledgement(_ normalized: String, words: Set<String>) -> Bool {
        if normalized.contains("can wait")
            || normalized.contains("a mistake")
            || normalized.contains("my mistake")
            || normalized.contains("should not be doing")
            || normalized.contains("should not open")
            || normalized.contains("should not use")
            || normalized.contains("do not need this")
            || normalized.contains("do not need to use")
            || normalized.contains("not a good")
            || normalized.contains("not good")
            || normalized.contains("not be wise")
            || normalized.contains("not very wise")
            || normalized.contains("not the best")
            || normalized.contains("something better")
            || normalized.contains("better spent")
            || normalized.contains("against my goals")
            || normalized.contains("goes against my goals")
            || normalized.contains("put my phone down")
            || words.contains("procrastinating")
            || (words.contains("regret") && !words.isDisjoint(with: decisionContext)) {
            return true
        }

        return !words.isDisjoint(with: negativeJudgements)
            && !words.isDisjoint(with: decisionContext)
    }

    private static func expressesOppositeIntent(_ normalized: String) -> Bool {
        let vetoes = [
            "not a bad", "not bad", "not a poor", "not poor", "not wrong", "not unwise",
            "not wasting", "not a waste", "do not regret", "will not regret", "not a mistake",
            "not procrastinating", "not here to procrastinate", "not a distraction", "not distracting",
            "not against my goals", "not pointless", "not unnecessary", "not impulsive",
            "not inconsistent", "do not need to stop", "should not avoid", "do not need to avoid",
            "i need to", "i actually need", "i have to", "i must", "i am required",
            "it is required", "this is required", "this is necessary", "it is necessary",
            "this is urgent", "something urgent", "for an emergency", "for work", "for school",
            "cannot wait", "can not wait", "need my attention", "needs my attention",
            "a good choice", "a good decision", "a good reason", "a great choice", "a great decision",
            "the right choice", "the right decision", "the best choice", "a smart decision",
            "wise to open", "healthy for me", "healthy habit", "help me", "helps me",
            "supports my goals", "support my goals", "productive use", "well spent", "worth my time",
            "worth it", "improve my day", "meaningful thing", "meaningful use", "deserves my time",
            "my focus belongs", "my attention belongs", "consistent with what i want",
            "consistent with the boundary", "glad i", "opening this deliberately", "carefully decided",
            "stop putting things off", "address my priority", "address my priorities",
            "important tool", "this is the task", "want to continue", "choose to continue",
            "keep scrolling", "unlock this", "access now", "still want to continue"
        ]
        return vetoes.contains { normalized.contains($0) }
    }

    private static func isQuestion(_ transcript: String, normalized: String) -> Bool {
        if transcript.contains("?") { return true }
        let questionOpeners = [
            "am i ", "are we ", "can i ", "can this ", "could this ", "did i ", "do i ",
            "does this ", "is my ", "is this ", "should i ", "was this ", "why is ", "would this "
        ]
        return questionOpeners.contains { normalized.hasPrefix($0) }
    }

    private static func isReportedOrHistorical(_ normalized: String) -> Bool {
        let markers = [
            "the phrase", "the sentence", "the words", "the prompt", "the screen", "the article",
            "the headline", "the app says", "it says", "it claims", "repeat ", "quote ", "quoting ",
            "my friend", "my coworker", "someone told", "someone said", "they are", "he is", "she is",
            "yesterday", "last week", "earlier but now", "used to regret", "used to waste"
        ]
        return markers.contains { normalized.contains($0) }
    }
}
