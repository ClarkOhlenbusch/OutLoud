import Foundation

/// Owns the lifetime of a typed check. Cancelling invalidates its result even
/// when the underlying on-device inference cannot be interrupted.
@MainActor
final class TypedChallengeController: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var attemptID = UUID()
    private let classify: (String) async -> AcknowledgementMatch
    private let timeout: UInt64

    init(classify: ((String) async -> AcknowledgementMatch)? = nil,
         timeout: UInt64 = 15_000_000_000) {
#if DEBUG && targetEnvironment(simulator)
        self.classify = classify ?? UITestScenario.makeClassifier()
            ?? { await FlexibleAcknowledgementMatcher.evaluate(transcript: $0) }
#else
        self.classify = classify ?? { await FlexibleAcknowledgementMatcher.evaluate(transcript: $0) }
#endif
        self.timeout = timeout
    }

    func cancel() {
        attemptID = UUID()
        task?.cancel()
        task = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        isChecking = false
        errorMessage = nil
    }

    func submit(_ text: String, phrases: [String], acceptsSimilar: Bool,
                onMatch: @escaping () -> Void, onReject: @escaping () -> Void) {
        guard !isChecking else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cancel()
        if text.contains("?") || text.contains("？") {
            errorMessage = "Questions are not acknowledgments. State it as a fact."
            onReject()
        } else if PhraseMatcher.matches(transcript: text, expectedPhrases: phrases)
                    || (acceptsSimilar && ExplicitAcknowledgementMatcher.matches(text)) {
            onMatch()
        } else if !acceptsSimilar {
            errorMessage = "Phrase didn’t match. Check the spelling and try again."
            onReject()
        } else {
            isChecking = true
            let id = attemptID
            timeoutTask = Task { [weak self, timeout] in
                do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                guard let self, self.attemptID == id else { return }
                self.cancel()
                self.errorMessage = "Checking your words took too long. Try again or type a specific phrase."
            }
            task = Task { [weak self, classify] in
                let result = await classify(text)
                guard let self, !Task.isCancelled, self.attemptID == id else { return }
                self.cancel()
                switch result {
                case .accepted: onMatch()
                case .rejected:
                    self.errorMessage = "I couldn’t match that acknowledgment. Try again or type a specific phrase."
                    onReject()
                case .unavailable:
                    self.errorMessage = "Recognition model couldn’t evaluate your words. Please try a specific phrase."
                }
            }
        }
    }
}
