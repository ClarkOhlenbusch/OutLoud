import Foundation

/// Input and score validation shared by the app's learned matching path and trainer.
enum AcknowledgementDecision {
    static let label = "acknowledges"
    static let policyVersion = "2"

    static func modelInput(_ transcript: String) -> String? {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Speech can spell the same contraction with either apostrophe. Expand
        // only unambiguous forms, preserving punctuation and the full statement.
        for (pattern, replacement) in [
            (#"\bi['’]m\b"#, "I am"), (#"\bisn['’]t\b"#, "is not"),
            (#"\bdon['’]t\b"#, "do not"), (#"\bcan['’]t\b"#, "cannot"),
            (#"\bwon['’]t\b"#, "will not")
        ] {
            text = text.replacingOccurrences(of: pattern, with: replacement,
                                            options: [.regularExpression, .caseInsensitive])
        }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        // Bound latency and avoid classifying a truncated prefix that omits a
        // later negation/concession. Reject long speech instead of clipping it.
        guard (2...80).contains(words.count), text.utf16.count <= 400,
              text.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return nil }
        return text
    }

    static func accepts(score: Double?, threshold: Double) -> Bool {
        guard let score, score.isFinite, (0...1).contains(score),
              threshold.isFinite, (0.5...1).contains(threshold) else { return false }
        return score >= threshold
    }
}
