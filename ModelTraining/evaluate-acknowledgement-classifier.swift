import CoreML
import Darwin
import CryptoKit
import Foundation

private let labels = [AcknowledgementDecision.label, "other"]
private typealias Corpus = [String: [String]]

private struct TrainingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct ScoredExample: Codable {
    let text: String
    let positive: Bool
    let score: Double?
}

private struct ValidationReport: Codable {
    let modelSHA256: String
    let calibrationSHA256: String
    let modelCalibrationSHA256: String?
    let evaluation: Evaluation
    let passes: Bool
    let errors: [ScoredExample]
}

private func fingerprint(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

private struct Evaluation: Codable {
    let threshold: Double
    var truePositives = 0
    var falsePositives = 0
    var trueNegatives = 0
    var falseNegatives = 0
    var precision: Double { ratio(truePositives, truePositives + falsePositives) }
    var recall: Double { ratio(truePositives, truePositives + falseNegatives) }
    var falsePositiveRate: Double { ratio(falsePositives, falsePositives + trueNegatives) }
    var passes: Bool { precision >= 0.95 && recall >= 0.80 && falsePositiveRate <= 0.03 }
    private func ratio(_ a: Int, _ b: Int) -> Double { b == 0 ? 0 : Double(a) / Double(b) }
    var summary: String {
        String(format: "threshold %.3f: precision %.1f%%, recall %.1f%%, FPR %.1f%% (TP %d, FP %d, TN %d, FN %d)",
               threshold, precision * 100, recall * 100, falsePositiveRate * 100,
               truePositives, falsePositives, trueNegatives, falseNegatives)
    }
}

private func evaluate(_ examples: [ScoredExample], threshold: Double) -> Evaluation {
    var result = Evaluation(threshold: threshold)
    for example in examples {
        let accepted = AcknowledgementDecision.modelInput(example.text) != nil
            && AcknowledgementDecision.accepts(score: example.score, threshold: threshold)
        switch (example.positive, accepted) {
        case (true, true): result.truePositives += 1
        case (false, true): result.falsePositives += 1
        case (false, false): result.trueNegatives += 1
        case (true, false): result.falseNegatives += 1
        }
    }
    return result
}

private func score(_ corpus: Corpus, predict: (String) throws -> Double?) rethrows -> [ScoredExample] {
    try labels.flatMap { label in
        try corpus[label, default: []].map { text in
            let input = AcknowledgementDecision.modelInput(text)
            return ScoredExample(text: text, positive: label == AcknowledgementDecision.label,
                                 score: try input.flatMap(predict))
        }
    }
}

private func printErrors(_ examples: [ScoredExample], threshold: Double) {
    for example in examples {
        let accepted = AcknowledgementDecision.modelInput(example.text) != nil
            && AcknowledgementDecision.accepts(score: example.score, threshold: threshold)
        if accepted != example.positive {
            print("\(accepted ? "false positive" : "false negative") \(example.score ?? 0): \(example.text)")
        }
    }
}

private func loadCorpora(_ directory: URL) throws -> [String: Corpus] {
    var result: [String: Corpus] = [:]
    var seen: [String: String] = [:]
    for split in ["training", "calibration", "test"] {
        let url = directory.appendingPathComponent("acknowledgement-\(split).json")
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        guard Set(corpus.keys) == Set(labels) else { throw TrainingError(message: "Invalid labels in \(split)") }
        for label in labels {
            guard corpus[label, default: []].count >= 20 else { throw TrainingError(message: "Too few \(label) examples in \(split)") }
            for text in corpus[label, default: []] {
                let key = PhraseMatcher.normalize(text)
                guard !key.isEmpty, seen[key] == nil else {
                    throw TrainingError(message: "Empty/duplicate/overlapping example in \(split): \(text); previous: \(seen[key] ?? "none")")
                }
                seen[key] = "\(split)/\(label)"
            }
        }
        result[split] = corpus
    }
    return result
}

@main
private enum Evaluator {
    static func main() {
        setbuf(stdout, nil)
        do { try run() } catch {
            fputs("Evaluation failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = directory.deletingLastPathComponent()
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--tokenize", arguments.count == 4 {
            let vocabulary = try String(contentsOfFile: arguments[1], encoding: .utf8)
            guard let tokenizer = AcknowledgementTokenizer(vocabulary: vocabulary) else {
                throw TrainingError(message: "Invalid tokenizer vocabulary")
            }
            let texts = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
            let ids = texts.map { text in
                AcknowledgementDecision.modelInput(text).flatMap { tokenizer.encode($0)?.ids }
            }
            try JSONEncoder().encode(ids).write(to: URL(fileURLWithPath: arguments[3]))
            return
        }
        let corpora = try loadCorpora(directory)
        if arguments == ["--check-data"] {
            print("Validated labels and disjoint normalized corpora.")
            return
        }
        guard arguments.count == 3, ["--validate-current", "--calibration-only", "--promote"].contains(arguments[0]) else {
            throw TrainingError(message: "Usage: --validate-current|--calibration-only|--promote candidate.mlmodel vocabulary.txt")
        }
        let candidate = URL(fileURLWithPath: arguments[1])
        let vocabulary = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        let compiled = try MLModel.compileModel(at: candidate)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let coreModel = try MLModel(contentsOf: compiled, configuration: configuration)
        let inference = try AcknowledgementInference(model: coreModel, vocabulary: vocabulary)
        let metadata = coreModel.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        // Diagnostic evaluation permits new calibration data, but never changes the
        // threshold, model metadata, promotion report, or final-test exposure.
        if arguments[0] == "--validate-current" {
            let examples = try score(corpora["calibration"]!) { try inference.score(transcript: $0) }
            let result = evaluate(examples, threshold: inference.threshold)
            let report = ValidationReport(
                modelSHA256: try fingerprint(candidate),
                calibrationSHA256: try fingerprint(directory.appendingPathComponent("acknowledgement-calibration.json")),
                modelCalibrationSHA256: metadata?["calibrationSHA256"],
                evaluation: result,
                passes: result.passes,
                errors: examples.filter {
                    AcknowledgementDecision.accepts(score: $0.score, threshold: inference.threshold) != $0.positive
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
            return
        }
        for split in ["training", "calibration", "test"] {
            let data = try Data(contentsOf: directory.appendingPathComponent("acknowledgement-\(split).json"))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard metadata?["\(split)SHA256"] == hash else { throw TrainingError(message: "Candidate corpus changed: \(split)") }
        }
        var report: [String: Evaluation] = [:]
        let splits = arguments[0] == "--promote" ? ["calibration", "test"] : ["calibration"]
        for split in splits {
            let examples = try score(corpora[split]!) { try inference.score(transcript: $0) }
            let result = evaluate(examples, threshold: inference.threshold)
            print("\(split): " + result.summary)
            printErrors(examples, threshold: inference.threshold)
            guard result.passes else { throw TrainingError(message: "\(split) failed. Shipping model untouched. Do not tune against final-test errors.") }
            report[split] = result
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reportData = try encoder.encode(report)
        try reportData.write(to: candidate.deletingPathExtension().appendingPathExtension("evaluation.json"), options: .atomic)
        if arguments[0] == "--promote" {
            let models = root.appendingPathComponent("OutLoud/Models")
            try vocabulary.write(to: models.appendingPathComponent("AcknowledgementVocabulary.txt"), options: .atomic)
            try Data(contentsOf: candidate).write(to: models.appendingPathComponent("FlexibleAcknowledgementClassifier.mlmodel"), options: .atomic)
            try reportData.write(to: models.appendingPathComponent("FlexibleAcknowledgementClassifier.evaluation.json"), options: .atomic)
            print("Promoted exact candidate after CPU-only evaluation of the complete Swift inference path.")
        }
    }
}
