import Foundation

/// Uncased BERT BasicTokenizer + greedy WordPiece. The vocabulary ships with
/// the model; no OS language asset, network request, or third-party runtime.
struct AcknowledgementTokenizer {
    static let sequenceLength = 128
    private let vocabulary: [String: Int32]

    init?(vocabulary text: String) {
        let tokens = text.split(separator: "\n", omittingEmptySubsequences: false)
        var vocabulary: [String: Int32] = [:]
        for (index, token) in tokens.enumerated() where !token.isEmpty {
            guard vocabulary[String(token)] == nil else { return nil }
            vocabulary[String(token)] = Int32(index)
        }
        guard vocabulary["[PAD]"] == 0, vocabulary["[UNK]"] == 100,
              vocabulary["[CLS]"] == 101, vocabulary["[SEP]"] == 102 else { return nil }
        self.vocabulary = vocabulary
    }

    func encode(_ text: String) -> (ids: [Int32], mask: [Int32])? {
        // Reserved model markers are not spoken words. Do not let a literal
        // marker in external input alter the sequence framing.
        guard !["[CLS]", "[SEP]", "[PAD]", "[UNK]", "[MASK]"].contains(where: text.contains) else { return nil }
        var ids: [Int32] = [101]
        for token in Self.basicTokens(text) {
            let characters = Array(token.unicodeScalars)
            if characters.count > 100 { return nil }
            var start = 0
            var pieces: [Int32] = []
            while start < characters.count {
                var end = characters.count
                var found: Int32?
                while start < end {
                    let piece = String(String.UnicodeScalarView(characters[start..<end]))
                    if let id = vocabulary[(start == 0 ? "" : "##") + piece] {
                        found = id
                        break
                    }
                    end -= 1
                }
                guard let found else { pieces = [100]; break }
                pieces.append(found)
                start = end
            }
            ids.append(contentsOf: pieces)
            // Never truncate: a suffix can change the meaning of an admission.
            guard ids.count < Self.sequenceLength else { return nil }
        }
        ids.append(102)
        let padding = Self.sequenceLength - ids.count
        let mask = Array(repeating: Int32(1), count: ids.count) + Array(repeating: Int32(0), count: padding)
        ids += Array(repeating: 0, count: padding)
        return (ids, mask)
    }

    private static func basicTokens(_ text: String) -> [String] {
        var cleaned = ""
        for scalar in text.unicodeScalars {
            if scalar == "\t" || scalar == "\n" || scalar == "\r"
                || scalar.properties.generalCategory == .spaceSeparator {
                cleaned.append(" ")
            } else if scalar.value == 0 || scalar.value == 0xFFFD
                        || scalar.properties.generalCategory == .control
                        || scalar.properties.generalCategory == .format {
                continue
            } else if isChinese(scalar.value) {
                cleaned += " " + String(scalar) + " "
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }
        let lowered = cleaned.precomposedStringWithCanonicalMapping.lowercased().decomposedStringWithCanonicalMapping
        var tokens: [String] = []
        var current = ""
        func finish() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }
        for scalar in lowered.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue }
            if scalar.properties.isWhitespace { finish() }
            else if isPunctuation(scalar) { finish(); tokens.append(String(scalar)) }
            else { current.unicodeScalars.append(scalar) }
        }
        finish()
        return tokens
    }

    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if (33...47).contains(value) || (58...64).contains(value)
            || (91...96).contains(value) || (123...126).contains(value) { return true }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }

    private static func isChinese(_ value: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
            || (0x20000...0x2A6DF).contains(value) || (0x2A700...0x2B73F).contains(value)
            || (0x2B740...0x2B81F).contains(value) || (0x2B820...0x2CEAF).contains(value)
            || (0xF900...0xFAFF).contains(value) || (0x2F800...0x2FA1F).contains(value)
    }
}
