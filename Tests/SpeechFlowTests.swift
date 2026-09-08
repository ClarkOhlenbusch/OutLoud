import XCTest
@testable import OutLoud

final class SpeechFlowTests: XCTestCase {
    @MainActor
    func testPartialAcknowledgementFollowedByNecessaryUseNeverUnlocks() {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture)
        var matches = 0
        controller.requestAndStart(expectedPhrases: [], acceptsSimilarAcknowledgements: true) { matches += 1 }
        capture.permissions[0](true)
        capture.receivers[0](.transcript("I am making a bad choice", isFinal: false))
        XCTAssertEqual(matches, 0)
        XCTAssertTrue(controller.isListening)
        capture.receivers[0](.transcript("I am making a bad choice but I need this for work", isFinal: true))
        XCTAssertEqual(matches, 0)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.isListening)
    }

    @MainActor
    func testFinalAcknowledgementUnlocksOnceAndLateCallbacksAreIgnored() {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture)
        var matches = 0
        controller.requestAndStart(expectedPhrases: [], acceptsSimilarAcknowledgements: true) { matches += 1 }
        capture.permissions[0](true)
        let receive = capture.receivers[0]
        receive(.transcript("I am making a bad choice", isFinal: true))
        receive(.transcript("I am making a bad choice", isFinal: true))
        receive(.failure("Cancellation callback"))
        XCTAssertEqual(matches, 1)
        XCTAssertNil(controller.errorMessage)
        XCTAssertFalse(controller.isListening)
    }

    @MainActor
    func testCancelDuringPermissionPromptCannotStartMicrophone() {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture)
        controller.requestAndStart(expectedPhrases: [], acceptsSimilarAcknowledgements: true) { XCTFail("Cancelled") }
        controller.stop()
        capture.permissions[0](true)
        XCTAssertEqual(capture.starts, 0)
    }

    @MainActor
    func testPermissionDenialAndUnavailableRecognizerCanRetry() {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture)
        var matches = 0
        func start() {
            controller.requestAndStart(expectedPhrases: ["this can wait"], acceptsSimilarAcknowledgements: false) { matches += 1 }
        }
        start()
        capture.permissions[0](false)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(capture.starts, 0)
        capture.startError = NSError(domain: "UnavailableRecognizer", code: 1)
        start()
        capture.permissions[1](true)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.isListening)
        capture.startError = nil
        start()
        capture.permissions[2](true)
        capture.receivers[0](.transcript("this can wait", isFinal: true))
        XCTAssertEqual(matches, 1)
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    func testOldSessionCannotUnlockOrFailNewSession() {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture)
        var matches = 0
        for _ in 0..<2 {
            controller.requestAndStart(expectedPhrases: ["this can wait"], acceptsSimilarAcknowledgements: false) { matches += 1 }
            capture.permissions.last?(true)
        }
        capture.receivers[0](.transcript("this can wait", isFinal: true))
        capture.receivers[0](.failure("Old task error"))
        XCTAssertTrue(controller.isListening)
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(matches, 0)
        capture.receivers[1](.transcript("this can wait", isFinal: true))
        XCTAssertEqual(matches, 1)
    }

    @MainActor
    func testSilenceEndsCaptureButWaitsForFinalTranscript() {
        let capture = FakeSpeechCapture()
        var date = Date()
        let controller = SpeechChallengeController(capture: capture, now: { date })
        var matches = 0
        controller.requestAndStart(expectedPhrases: ["this can wait"], acceptsSimilarAcknowledgements: false) { matches += 1 }
        capture.permissions[0](true)
        capture.receivers[0](.transcript("this can wait", isFinal: false))
        capture.receivers[0](.level(0.8))
        date.addTimeInterval(0.5)
        capture.receivers[0](.level(0))
        XCTAssertEqual(capture.finishes, 0)
        date.addTimeInterval(1)
        capture.receivers[0](.level(0))
        XCTAssertEqual(capture.finishes, 1)
        XCTAssertTrue(controller.isFinalizing)
        XCTAssertEqual(matches, 0)
        capture.receivers[0](.transcript("this can wait", isFinal: true))
        XCTAssertEqual(matches, 1)
        XCTAssertFalse(controller.isFinalizing)
    }

    @MainActor
    func testMissingFinalResultTimesOutWithRetryAvailable() async throws {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture, finalizationTimeout: 1_000_000)
        controller.requestAndStart(expectedPhrases: [], acceptsSimilarAcknowledgements: true) { XCTFail("No final result") }
        capture.permissions[0](true)
        controller.finishSpeaking()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.isFinalizing)
    }
}
