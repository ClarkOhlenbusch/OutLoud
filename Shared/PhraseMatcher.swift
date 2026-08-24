import Foundation

enum PhraseMatcher {
    static func matches(
        transcript: String,
        expectedPhrases: [String]
    ) -> Bool {
        expectedPhrases.contains(where: { matches(transcript: transcript, expected: $0) })
    }

    static func matches(transcript: String, expected: String) -> Bool {
        let heard = normalize(transcript)
        let target = normalize(expected)
        guard !heard.isEmpty, !target.isEmpty else { return false }

        if heard == target { return true }

        // Speech recognition may add words before or after the phrase. Pad both
        // sides so short phrases only match complete words, never substrings.
        if " \(heard) ".contains(" \(target) ") { return true }

        let distance = editDistance(heard, target)
        let longest = max(heard.count, target.count)
        if !heard.contains(" "),
           !target.contains(" "),
           longest >= 4,
           distance == 1 {
            return true
        }
        // Short speech-recognition substitutions can require several character
        // edits (for example, "weight" for "wait") even when only one spoken
        // word was misunderstood.
        return Double(distance) / Double(longest) <= 0.20
    }

    static func phrases(from value: String) -> [String] {
        var seen = Set<String>()
        return value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { phrase in
                guard !phrase.isEmpty else { return false }
                return seen.insert(normalize(phrase)).inserted
            }
    }

    static func normalize(_ value: String) -> String {
        var normalized = value.lowercased()
        let replacements = [
            "i'm": "i am",
            "i’m": "i am",
            "isn't": "is not",
            "isn’t": "is not",
            "it's": "it is",
            "it’s": "it is",
            "don't": "do not",
            "don’t": "do not"
        ]
        for (source, replacement) in replacements {
            normalized = normalized.replacingOccurrences(of: source, with: replacement)
        }
        return normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[right.count]
    }
}
