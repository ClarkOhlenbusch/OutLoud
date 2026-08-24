import XCTest
@testable import OutLoud

final class PhraseMatcherTests: XCTestCase {
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

    func testFlexibleAcknowledgementMatchesParaphrase() {
        XCTAssertTrue(FlexibleAcknowledgementMatcher.matches(
            transcript: "I acknowledge this is a poor decision"
        ))
    }

    func testFlexibleAcknowledgementRejectsOppositeMeaning() {
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "I need to use this app"
        ))
    }

    func testFlexibleAcknowledgementRejectsPositiveStatement() {
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "I am having a good time here"
        ))
    }

    func testFlexibleAcknowledgementRejectsNegatedBadChoice() {
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "This isn't a bad choice"
        ))
    }

    func testFlexibleAcknowledgementUnderstandsLessLiteralAdmission() {
        XCTAssertTrue(FlexibleAcknowledgementMatcher.matches(
            transcript: "I realize this may not be wise"
        ))
    }

    func testFlexibleAcknowledgementRejectsUnrelatedSpeech() {
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "The weather is nice today"
        ))
    }

    func testFlexibleAcknowledgementModelIsBundled() {
        XCTAssertTrue(FlexibleAcknowledgementMatcher.isModelAvailable)
    }

    func testFlexibleAcknowledgementUsesModelForNovelAdmission() throws {
        guard FlexibleAcknowledgementMatcher.areModelAssetsAvailable else {
            throw XCTSkip("Simulator does not include the downloadable Natural Language contextual-embedding asset.")
        }
        XCTAssertTrue(FlexibleAcknowledgementMatcher.matches(
            transcript: "I know scrolling would take me away from my plans"
        ))
    }

    func testFlexibleAcknowledgementSafetyGateOverridesModelFalsePositive() {
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "I am definitely not here to procrastinate"
        ))
    }

    func testFlexibleAcknowledgementRejectsUnrelatedNegativeHabit() {
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "My old habit was biting my nails"
        ))
    }

    func testFlexibleAcknowledgementRejectsQuestion() {
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "Is this app a waste of time?"
        ))
    }

    func testFlexibleAcknowledgementRejectsReportedPrompt() {
        XCTAssertFalse(FlexibleAcknowledgementMatcher.matches(
            transcript: "The prompt says I am making a bad choice"
        ))
    }

    func testFlexibleAcknowledgementRejectsNecessaryConcession() {
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
