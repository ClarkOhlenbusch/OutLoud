import CoreML
import XCTest
@testable import OutLoud

final class PhraseMatcherTests: XCTestCase {
    func testEveryRequiredAcknowledgementRegressionWithBundledModel() throws {
        try requireBundledModel()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "acknowledgement-regressions", withExtension: "json"))
        let cases = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
        XCTAssertEqual(Set(cases.keys), ["acknowledges", "other"])
        for label in ["acknowledges", "other"] {
            let texts = try XCTUnwrap(cases[label])
            XCTAssertFalse(texts.isEmpty)
            for text in texts {
                XCTAssertEqual(FlexibleAcknowledgementMatcher.matches(transcript: text), label == "acknowledges", text)
            }
        }
    }

    func testBasicAcknowledgementsWithSpeechPunctuation() throws {
        try requireBundledModel()
        for text in ["this is a bad choice", "This is a bad choice.", "This is a bad choice!",
                     "I am making a bad choice.", "I'm wasting time", "I am wasting my time",
                     "This is a waste of time", "I'm procrastinating", "This is a poor choice",
                     "I acknowledge this is a bad choice", "This app is distracting me"] {
            XCTAssertTrue(FlexibleAcknowledgementMatcher.matches(transcript: text), text)
        }
    }

    func testBadChoiceQuestionsAndDenialsStillRejectWithPunctuation() throws {
        try requireBundledModel()
        for text in ["This is a bad choice?", "This is not a bad choice",
                     "This is not a bad choice.", "This is not a bad choice!"] {
            XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(transcript: text), text)
        }
    }

    private func requireBundledModel() throws {
        XCTAssertTrue(FlexibleAcknowledgementMatcher.isModelAvailable)
    }

    func testClassifierRejectsMismatchedVocabulary() throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try FlexibleAcknowledgementClassifier(configuration: configuration).model
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AcknowledgementVocabulary", withExtension: "txt"))
        let original = try Data(contentsOf: url)
        XCTAssertNoThrow(try AcknowledgementInference(model: model, vocabulary: original))
        var words = try XCTUnwrap(String(data: original, encoding: .utf8)).components(separatedBy: "\n")
        words.swapAt(200, 201)
        let modified = words.joined(separator: "\n")
        XCTAssertNotNil(AcknowledgementTokenizer(vocabulary: modified))
        XCTAssertThrowsError(try AcknowledgementInference(model: model, vocabulary: Data(modified.utf8)))
    }

    func testContractionNormalizationPreservesNegation() {
        XCTAssertEqual(AcknowledgementDecision.modelInput("I’m not wasting time"), "I am not wasting time")
        XCTAssertEqual(AcknowledgementDecision.modelInput("This isn't a bad choice"), "This is not a bad choice")
        XCTAssertEqual(AcknowledgementDecision.modelInput("I don't need this app"), "I do not need this app")
        XCTAssertEqual(AcknowledgementDecision.modelInput("This can't wait"), "This cannot wait")
    }

    func testTokenizerRejectsOverflowAndReservedMarkers() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AcknowledgementVocabulary", withExtension: "txt"))
        let tokenizer = try XCTUnwrap(AcknowledgementTokenizer(vocabulary: String(contentsOf: url, encoding: .utf8)))
        XCTAssertNil(tokenizer.encode(String(repeating: "hello ", count: 127)))
        XCTAssertNil(tokenizer.encode("[CLS] bad [SEP]"))
        XCTAssertNil(AcknowledgementTokenizer(vocabulary: "bad\nthis\nhere"))
        let encoded = try XCTUnwrap(tokenizer.encode("I am making a bad choice"))
        XCTAssertEqual(encoded.ids.count, 128)
        XCTAssertEqual(encoded.mask.count, 128)
        XCTAssertEqual(encoded.ids.prefix(8), [101, 1045, 2572, 2437, 1037, 2919, 3601, 102])
        XCTAssertEqual(encoded.mask.prefix(9), [1, 1, 1, 1, 1, 1, 1, 1, 0])
    }

    func testModelDecisionRequiresAValidScore() {
        for text in ["This sandwich is bad", "The weather here is bad", "I had a bad time at dinner", "The soup can wait", "I am making a bad choice"] {
            XCTAssertNotNil(AcknowledgementDecision.modelInput(text))
            XCTAssertFalse(AcknowledgementDecision.accepts(score: nil, threshold: 0.8), text)
            XCTAssertFalse(AcknowledgementDecision.accepts(score: 0.4, threshold: 0.8), text)
        }
    }

    func testExplicitAcknowledgementsRequireTheWholeUnqualifiedStatement() {
        for text in ["This is not a bad choice", "This is a bad choice?",
                     "“This is a bad choice”", "The prompt says this is a bad choice",
                     "This is a bad choice but I need this for work",
                     "This is a bad choice of shoes", "Was this a bad choice?",
                     "Yesterday I said this is a bad choice",
                     "This is a bad choice. Actually it is necessary."] {
            XCTAssertFalse(ExplicitAcknowledgementMatcher.matches(text), text)
        }
        XCTAssertFalse(ExplicitAcknowledgementMatcher.matches("I know scrolling would take me away from my plans"))
    }

    func testModelSeesFullStatementIncludingNegationsAndConcessions() {
        for text in ["Checking this would only help me put things off", "I need to admit I am procrastinating", "I am making a bad choice but I need this for work"] {
            XCTAssertEqual(AcknowledgementDecision.modelInput(text), text)
        }
    }

    func testLongInputIsRejectedInsteadOfTruncatingItsEnding() {
        XCTAssertNil(AcknowledgementDecision.modelInput(String(repeating: "I am wasting time ", count: 30) + "but this is necessary"))
        XCTAssertNil(AcknowledgementDecision.modelInput("bad"))
        XCTAssertNil(AcknowledgementDecision.modelInput("   "))
    }

    func testInvalidOrLowScoresNeverUnlock() {
        for score in [Double.nan, .infinity, -.infinity, -0.1, 1.1, 0.79] {
            XCTAssertFalse(AcknowledgementDecision.accepts(score: score, threshold: 0.8))
        }
        for threshold in [Double.nan, .infinity, 0.0, 1.1] {
            XCTAssertFalse(AcknowledgementDecision.accepts(score: 1, threshold: threshold))
        }
        XCTAssertTrue(AcknowledgementDecision.accepts(score: 0.8, threshold: 0.8))
    }

    func testUnrelatedNegativeSpeechDoesNotUnlock() throws {
        try requireBundledModel()
        for text in ["This sandwich is bad", "The weather here is bad", "I had a bad time at dinner", "The soup can wait", "This app has bad reviews"] {
            XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(transcript: text), text)
        }
    }

    func testOwnWordsCannotBypassModelThroughSavedPhrases() throws {
        try requireBundledModel()
        let rejected = [
            "I am making a good choice",
            "I am not making a bad choice",
            "I am making a bad choice?",
            "The prompt says I am making a bad choice",
            "I am making a bad choice but I need to use this app for work"
        ]
        for transcript in rejected {
            XCTAssertFalse(ChallengePhraseMatcher.matches(
                transcript: transcript,
                expectedPhrases: ["I am making a bad choice", transcript],
                acceptsSimilarAcknowledgements: true
            ), transcript)
        }
    }

    func testOwnWordsStillAcceptsAcknowledgements() throws {
        try requireBundledModel()
        for transcript in [
            "I am making a bad choice",
            "I'm making a bad choice",
            "I acknowledge this is a poor decision",
            "I realize this may not be wise"
        ] {
            XCTAssertTrue(ChallengePhraseMatcher.matches(
                transcript: transcript,
                expectedPhrases: ["My custom phrase"],
                acceptsSimilarAcknowledgements: true
            ), transcript)
        }
    }

    func testSpecificPhrasesCanStillUseCustomWording() {
        XCTAssertTrue(ChallengePhraseMatcher.matches(
            transcript: "I choose to continue",
            expectedPhrases: ["I choose to continue"],
            acceptsSimilarAcknowledgements: false
        ))
        XCTAssertFalse(ChallengePhraseMatcher.matches(
            transcript: "I am making a bad choice",
            expectedPhrases: ["My custom phrase"],
            acceptsSimilarAcknowledgements: false
        ))
    }

    func testPhraseSimilarityDoesNotAcceptChangedMeaning() {
        for transcript in [
            "I am making a good choice",
            "I am not making a bad choice",
            "The prompt says I am making a bad choice",
            "I am making a bad choice but I need to use this app"
        ] {
            XCTAssertFalse(PhraseMatcher.matches(
                transcript: transcript,
                expected: "I am making a bad choice"
            ), transcript)
        }
        XCTAssertFalse(PhraseMatcher.matches(transcript: "this cannot wait", expected: "this can wait"))
        XCTAssertFalse(PhraseMatcher.matches(transcript: "this can't wait", expected: "this can wait"))
    }

    func testExactPhraseMatchesIgnoringPunctuationAndCase() {
        XCTAssertTrue(PhraseMatcher.matches(
            transcript: "I am choosing to spend my time here.",
            expected: "i am choosing to spend my time here"
        ))
    }

    func testCommonContractionMatches() {
        XCTAssertTrue(PhraseMatcher.matches(
            transcript: "I'm making a bad choice",
            expected: "I am making a bad choice"
        ))
    }

    func testSmallRecognitionErrorMatches() {
        XCTAssertTrue(PhraseMatcher.matches(
            transcript: "this can weight",
            expected: "this can wait"
        ))
    }

    func testSingleUnusualWordAllowsOneRecognitionError() {
        XCTAssertTrue(PhraseMatcher.matches(
            transcript: "Chad",
            expected: "Chud"
        ))
    }

    func testAnyPhraseInCollectionCanMatch() {
        XCTAssertTrue(PhraseMatcher.matches(
            transcript: "this can wait",
            expectedPhrases: ["I am making a bad choice", "This can wait"]
        ))
    }

    func testPhraseCollectionParsingDropsBlankLinesAndDuplicates() {
        XCTAssertEqual(
            PhraseMatcher.phrases(from: "First phrase\n\n first phrase! \nSecond phrase"),
            ["First phrase", "Second phrase"]
        )
    }

    func testFlexibleAcknowledgementMatchesParaphrase() throws {
        try requireBundledModel()
        XCTAssertTrue(FlexibleAcknowledgementMatcher.matches(
            transcript: "I acknowledge this is a poor decision"
        ))
    }

    func testFlexibleAcknowledgementRejectsOppositeMeaning() throws {
        try requireBundledModel()
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "I need to use this app"
        ))
    }

    func testFlexibleAcknowledgementRejectsPositiveStatement() throws {
        try requireBundledModel()
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "I am having a good time here"
        ))
    }

    func testFlexibleAcknowledgementRejectsNegatedBadChoice() throws {
        try requireBundledModel()
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "This isn't a bad choice"
        ))
    }

    func testFlexibleAcknowledgementUnderstandsLessLiteralAdmission() throws {
        try requireBundledModel()
        XCTAssertTrue(FlexibleAcknowledgementMatcher.matches(
            transcript: "I realize this may not be wise"
        ))
    }

    func testFlexibleAcknowledgementRejectsUnrelatedSpeech() throws {
        try requireBundledModel()
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "The weather is nice today"
        ))
    }

    func testFlexibleAcknowledgementModelIsBundled() {
        XCTAssertTrue(FlexibleAcknowledgementMatcher.isModelAvailable)
    }

    func testFlexibleAcknowledgementUsesModelForNovelAdmission() throws {
        try requireBundledModel()
        XCTAssertTrue(FlexibleAcknowledgementMatcher.matches(
            transcript: "I know scrolling would take me away from my plans"
        ))
    }

    func testFlexibleAcknowledgementRejectsExplicitDenial() throws {
        try requireBundledModel()
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "I am definitely not here to procrastinate"
        ))
    }

    func testFlexibleAcknowledgementRejectsUnrelatedNegativeHabit() throws {
        try requireBundledModel()
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "My old habit was biting my nails"
        ))
    }

    func testFlexibleAcknowledgementRejectsQuestion() throws {
        try requireBundledModel()
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "Is this app a waste of time?"
        ))
    }

    func testFlexibleAcknowledgementRejectsReportedPrompt() throws {
        try requireBundledModel()
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "The prompt says I am making a bad choice"
        ))
    }

    func testFlexibleAcknowledgementRejectsNecessaryConcession() throws {
        try requireBundledModel()
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "This might waste time but it is required for work"
        ))
    }

    func testDifferentShortPhraseDoesNotMatchAtRelaxedThreshold() {
        XCTAssertFalse(PhraseMatcher.matches(
            transcript: "this can stop",
            expected: "this can wait"
        ))
    }

    func testDifferentIntentDoesNotMatch() {
        XCTAssertFalse(PhraseMatcher.matches(
            transcript: "open the app now",
            expected: "this can wait"
        ))
    }

    func testPhraseMatchesInsideLongerRecognitionResult() {
        XCTAssertTrue(PhraseMatcher.matches(
            transcript: "Okay, I am choosing to spend my time here now",
            expected: "I am choosing to spend my time here"
        ))
    }

    func testCurlyApostropheContractionMatches() {
        XCTAssertTrue(PhraseMatcher.matches(
            transcript: "I’m choosing to spend my time here",
            expected: "I am choosing to spend my time here"
        ))
    }

    func testWhitespaceAndSymbolsAreNormalized() {
        XCTAssertEqual(
            PhraseMatcher.normalize("  This—can... WAIT!  "),
            "this can wait"
        )
    }

    func testEmptyTranscriptDoesNotMatch() {
        XCTAssertFalse(PhraseMatcher.matches(
            transcript: "",
            expected: "this can wait"
        ))
    }

    func testEmptyExpectedPhraseDoesNotMatch() {
        XCTAssertFalse(PhraseMatcher.matches(
            transcript: "this can wait",
            expected: ""
        ))
    }

    func testIncompletePhraseDoesNotMatch() {
        XCTAssertFalse(PhraseMatcher.matches(
            transcript: "I am choosing",
            expected: "I am choosing to spend my time here"
        ))
    }

    func testShortPhraseDoesNotMatchBeginningOfAnotherWord() {
        XCTAssertFalse(PhraseMatcher.matches(
            transcript: "Nobody asked",
            expected: "no"
        ))
    }

    func testLargeRecognitionDifferenceDoesNotMatch() {
        XCTAssertFalse(PhraseMatcher.matches(
            transcript: "this should wait until tomorrow",
            expected: "this can wait"
        ))
    }
}
