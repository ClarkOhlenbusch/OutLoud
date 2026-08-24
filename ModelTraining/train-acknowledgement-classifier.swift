import CreateML
import Darwin
import Foundation
import NaturalLanguage

private let acknowledgementLabel = "acknowledges"
private let otherLabel = "other"
private let labels = [acknowledgementLabel, otherLabel]

private enum TrainingError: LocalizedError {
    case invalidCorpus(String)
    case qualityGate(String)

    var errorDescription: String? {
        switch self {
        case let .invalidCorpus(message), let .qualityGate(message): message
        }
    }
}

struct EvaluationResult {
    let threshold: Double
    let truePositives: Int
    let falsePositives: Int
    let trueNegatives: Int
    let falseNegatives: Int

    var precision: Double {
        ratio(truePositives, truePositives + falsePositives)
    }

    var recall: Double {
        ratio(truePositives, truePositives + falseNegatives)
    }

    var falsePositiveRate: Double {
        ratio(falsePositives, falsePositives + trueNegatives)
    }

    var accuracy: Double {
        ratio(truePositives + trueNegatives, truePositives + falsePositives + trueNegatives + falseNegatives)
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        denominator == 0 ? 0 : Double(numerator) / Double(denominator)
    }
}

private func loadCorpus(at url: URL) throws -> [String: [String]] {
    let data = try Data(contentsOf: url)
    let corpus = try JSONDecoder().decode([String: [String]].self, from: data)
    guard Set(corpus.keys) == Set(labels) else {
        throw TrainingError.invalidCorpus("\(url.lastPathComponent) must contain exactly: \(labels.joined(separator: ", ")).")
    }
    for label in labels {
        guard let examples = corpus[label], examples.count >= 20 else {
            throw TrainingError.invalidCorpus("\(url.lastPathComponent) needs at least 20 \(label) examples.")
        }
        guard examples.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw TrainingError.invalidCorpus("\(url.lastPathComponent) contains an empty \(label) example.")
        }
    }
    return corpus
}

private func normalized(_ value: String) -> String {
    value.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func validateNoConflictingExamples(in corpus: [String: [String]], name: String) throws {
    var ownerByExample: [String: String] = [:]
    for label in labels {
        for example in corpus[label, default: []] {
            let key = normalized(example)
            if let existingLabel = ownerByExample[key], existingLabel != label {
                throw TrainingError.invalidCorpus("\(name) puts \"\(example)\" in both labels.")
            }
            ownerByExample[key] = label
        }
    }
}

private func evaluate(
    model: MLTextClassifier,
    corpus: [String: [String]],
    threshold: Double
) throws -> EvaluationResult {
    var truePositives = 0
    var falsePositives = 0
    var trueNegatives = 0
    var falseNegatives = 0

    for label in labels {
        for example in corpus[label, default: []] {
            let confidence = try model.predictionWithConfidence(from: example)[acknowledgementLabel] ?? 0
            let predictedPositive = confidence >= threshold
            if label == acknowledgementLabel {
                predictedPositive ? (truePositives += 1) : (falseNegatives += 1)
            } else {
                predictedPositive ? (falsePositives += 1) : (trueNegatives += 1)
            }
        }
    }

    return EvaluationResult(
        threshold: threshold,
        truePositives: truePositives,
        falsePositives: falsePositives,
        trueNegatives: trueNegatives,
        falseNegatives: falseNegatives
    )
}

private func percent(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
}

let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repositoryRoot = scriptDirectory.deletingLastPathComponent()
let trainingURL = scriptDirectory.appendingPathComponent("acknowledgement-training.json")
let evaluationURL = scriptDirectory.appendingPathComponent("acknowledgement-evaluation.json")
let outputURL = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
    ?? repositoryRoot.appendingPathComponent("OutLoud/Models/FlexibleAcknowledgementClassifier.mlmodel")

let trainingCorpus = try loadCorpus(at: trainingURL)
let evaluationCorpus = try loadCorpus(at: evaluationURL)
try validateNoConflictingExamples(in: trainingCorpus, name: trainingURL.lastPathComponent)
try validateNoConflictingExamples(in: evaluationCorpus, name: evaluationURL.lastPathComponent)

let trainingExamples = labels.reduce(0) { $0 + trainingCorpus[$1, default: []].count }
let evaluationExamples = labels.reduce(0) { $0 + evaluationCorpus[$1, default: []].count }
print("Training on \(trainingExamples) examples; evaluating on \(evaluationExamples) held-out examples.")

var parameters = MLTextClassifier.ModelParameters(
    validation: .split(strategy: .fixed(ratio: 0.15, seed: 8_241)),
    algorithm: .transferLearning(.bertEmbedding, revision: 1),
    language: .english
)
parameters.maxIterations = 40

let classifier = try MLTextClassifier(trainingData: trainingCorpus, parameters: parameters)

let thresholdValues = Array(stride(from: 0.50, through: 0.75, by: 0.05))
    + Array(stride(from: 0.80, through: 0.99, by: 0.01))
let thresholds = try thresholdValues.map {
    try evaluate(model: classifier, corpus: evaluationCorpus, threshold: $0)
}
for result in thresholds {
    print(
        "threshold \(String(format: "%.2f", result.threshold)): "
            + "accuracy \(percent(result.accuracy)), precision \(percent(result.precision)), "
            + "recall \(percent(result.recall)), false-positive rate \(percent(result.falsePositiveRate))"
    )
}
fflush(stdout)

guard let shippingResult = thresholds
    .filter({ $0.precision >= 0.85 && $0.recall >= 0.20 && $0.falsePositiveRate <= 0.05 })
    .max(by: { lhs, rhs in
        if lhs.recall != rhs.recall { return lhs.recall < rhs.recall }
        if lhs.precision != rhs.precision { return lhs.precision < rhs.precision }
        return lhs.threshold > rhs.threshold
    }) else {
    throw TrainingError.qualityGate(
        "No threshold met precision >= 85%, recall >= 20%, and false-positive rate <= 5%."
    )
}
let shippingThreshold = shippingResult.threshold
print("Selected shipping threshold \(String(format: "%.3f", shippingThreshold)).")
for example in evaluationCorpus[otherLabel, default: []] {
    let confidence = try classifier.predictionWithConfidence(from: example)[acknowledgementLabel] ?? 0
    if confidence >= shippingThreshold {
        print("false positive \(String(format: "%.3f", confidence)): \(example)")
    }
}
for example in evaluationCorpus[acknowledgementLabel, default: []] {
    let confidence = try classifier.predictionWithConfidence(from: example)[acknowledgementLabel] ?? 0
    if confidence < shippingThreshold {
        print("false negative \(String(format: "%.3f", confidence)): \(example)")
    }
}
fflush(stdout)

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
if FileManager.default.fileExists(atPath: outputURL.path) {
    try FileManager.default.removeItem(at: outputURL)
}
try classifier.write(
    to: outputURL,
    metadata: MLModelMetadata(
        author: "OutLoud contributors",
        shortDescription: "Recognizes a spoken acknowledgement that opening a distracting app is avoidable or counterproductive.",
        license: "Copyright OutLoud contributors. Training sentences are original project data.",
        version: "1",
        additional: [
            "shippingThreshold": String(format: "%.2f", shippingThreshold),
            "trainingExamples": String(trainingExamples),
            "heldOutExamples": String(evaluationExamples)
        ]
    )
)

let outputBytes = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber
print("Wrote \(outputURL.path) (\(outputBytes?.intValue ?? 0) bytes).")
