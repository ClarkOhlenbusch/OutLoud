import XCTest

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
