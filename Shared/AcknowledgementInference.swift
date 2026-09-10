import CoreML
import CryptoKit
import Foundation

/// The exact inference path shared by the iPhone app and offline evaluation.
struct AcknowledgementInference {
    static let architecture = "bert-medium-wordpiece-v1"
    let threshold: Double
    private let model: MLModel
    private let tokenizer: AcknowledgementTokenizer

    init(model: MLModel, vocabulary: Data) throws {
        let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        let hash = SHA256.hash(data: vocabulary).map { String(format: "%02x", $0) }.joined()
        guard metadata?["policyVersion"] == AcknowledgementDecision.policyVersion,
              metadata?["architecture"] == Self.architecture,
              metadata?["vocabularySHA256"] == hash,
              let threshold = metadata?["shippingThreshold"].flatMap(Double.init),
              threshold.isFinite, (0.5...1).contains(threshold),
              let text = String(data: vocabulary, encoding: .utf8),
              let tokenizer = AcknowledgementTokenizer(vocabulary: text) else {
            throw NSError(domain: "OutLoud.Classifier", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Classifier metadata or vocabulary is invalid."])
        }
        self.model = model
        self.threshold = threshold
        self.tokenizer = tokenizer
    }

    func score(transcript: String) throws -> Double? {
        guard let text = AcknowledgementDecision.modelInput(transcript),
              let tokens = tokenizer.encode(text) else { return nil }
        let ids = try MLMultiArray(shape: [1, NSNumber(value: AcknowledgementTokenizer.sequenceLength)], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, NSNumber(value: AcknowledgementTokenizer.sequenceLength)], dataType: .int32)
        for index in tokens.ids.indices {
            ids[index] = NSNumber(value: tokens.ids[index])
            mask[index] = NSNumber(value: tokens.mask[index])
        }
        let input = try MLDictionaryFeatureProvider(dictionary: ["input_ids": ids, "attention_mask": mask])
        let output = try model.prediction(from: input)
        guard let probabilities = output.featureValue(for: "probabilities")?.multiArrayValue,
              probabilities.count == 2,
              probabilities[1].doubleValue.isFinite else {
            throw NSError(domain: "OutLoud.Classifier", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Classifier returned invalid probabilities."])
        }
        return probabilities[1].doubleValue
    }

    func matches(transcript: String) throws -> Bool {
        AcknowledgementDecision.accepts(score: try score(transcript: transcript), threshold: threshold)
    }
}
