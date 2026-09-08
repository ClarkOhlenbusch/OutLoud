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

        // Permit conversational filler, but not arbitrary surrounding speech
        // that could negate, quote, or qualify the saved phrase.
        var heardWords = heard.split(separator: " ").map(String.init)
        let targetWords = target.split(separator: " ").map(String.init)
        while heardWords.count > targetWords.count,
              let first = heardWords.first, ["okay", "ok", "well"].contains(first) {
            heardWords.removeFirst()
        }
        if heardWords.count > targetWords.count, heardWords.last == "now" {
            heardWords.removeLast()
        }
        if heardWords == targetWords { return true }

        let distance = editDistance(heard, target)
        let longest = max(heard.count, target.count)
        if !heard.contains(" "),
           !target.contains(" "),
           longest >= 4,
           distance == 1 {
            return true
        }
        // Character similarity does not preserve meaning (bad/good, can/can't).
        // Multiword phrases allow only known homophones, with no added words.
        guard heardWords.count == targetWords.count else { return false }
        let homophones: [Set<String>] = [["wait", "weight"], ["here", "hear"]]
        return zip(heardWords, targetWords).allSatisfy { heardWord, targetWord in
            heardWord == targetWord
                || homophones.contains { $0.contains(heardWord) && $0.contains(targetWord) }
        }
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
