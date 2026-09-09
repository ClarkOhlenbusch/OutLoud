import AVFoundation
import XCTest
@testable import OutLoud

final class SpeechFlowTests: XCTestCase {
    private let phrase = "I am wasting my time on Instagram."
    private var interruption: NSError { NSError(domain: "kAFAssistantErrorDomain", code: 1107) }

    @MainActor
    private func waitForRecovery(_ capture: FakeSpeechCapture, starts: Int = 2) async {
        let restarted = expectation(description: "Speech restarted")
        capture.onStart = { if capture.starts == starts { restarted.fulfill() } }
        await fulfillment(of: [restarted], timeout: 2)
        capture.onStart = nil
    }

    @MainActor
    func testServiceInterruptionReconnectsAndIgnoresOldCallbacks() async throws {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { true })
        var matches = 0
        controller.requestAndStart(expectedPhrases: [phrase], acceptsSimilarAcknowledgements: false) { matches += 1 }
        capture.permissions[0](true)
        let old = capture.receivers[0]
        old(.failure(interruption))
        XCTAssertTrue(controller.isRecovering)
        XCTAssertFalse(controller.isListening)
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.transcript, "")
        old(.transcript(phrase, isFinal: true))
        old(.failure(interruption))
        XCTAssertEqual(matches, 0)
        await waitForRecovery(capture)
        XCTAssertTrue(controller.isListening)
        XCTAssertFalse(controller.isRecovering)
        XCTAssertNotNil(controller.statusMessage)
        XCTAssertEqual(capture.permissions.count, 1)
        old(.failure(interruption))
        XCTAssertTrue(controller.isListening)
        let receive = try XCTUnwrap(capture.receivers.last)
        receive(.transcript(phrase, isFinal: false))
        XCTAssertEqual(matches, 0)
        receive(.transcript(phrase, isFinal: true))
        XCTAssertEqual(matches, 1)
        XCTAssertNil(controller.statusMessage)
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    func testInterruptionDuringFinalizationDiscardsPartialAndRequiresNewFinalPhrase() async {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { true })
        var matches = 0
        controller.requestAndStart(expectedPhrases: [phrase], acceptsSimilarAcknowledgements: false) { matches += 1 }
        capture.permissions[0](true)
        let old = capture.receivers[0]
        old(.transcript(phrase, isFinal: false))
        controller.finishSpeaking()
        XCTAssertTrue(controller.isFinalizing)
        old(.failure(interruption))
        XCTAssertFalse(controller.isFinalizing)
        XCTAssertEqual(controller.transcript, "")
        old(.transcript(phrase, isFinal: true))
        XCTAssertEqual(matches, 0)
        await waitForRecovery(capture)
        capture.receivers.last?(.transcript("I need this for work", isFinal: true))
        XCTAssertEqual(matches, 0)
        XCTAssertNotNil(controller.errorMessage)
    }

    @MainActor
    func testRepeatedInterruptionStopsAfterOneRecoveryAndManualRetryStartsFresh() async {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { true })
        var matches = 0
        func start() {
            controller.requestAndStart(expectedPhrases: [phrase], acceptsSimilarAcknowledgements: false) { matches += 1 }
            capture.permissions.last?(true)
        }
        start()
        capture.receivers[0](.failure(interruption))
        await waitForRecovery(capture)
        capture.receivers.last?(.failure(interruption))
        XCTAssertFalse(controller.isRecovering)
        XCTAssertFalse(controller.isListening)
        XCTAssertTrue(controller.errorMessage?.contains("Tap Try again") == true)
        XCTAssertFalse(controller.errorMessage?.contains("1107") == true)
        start()
        XCTAssertNil(controller.errorMessage)
        capture.receivers.last?(.failure(interruption))
        await waitForRecovery(capture, starts: 4)
        capture.receivers.last?(.transcript(phrase, isFinal: true))
        XCTAssertEqual(matches, 1)
    }

    @MainActor
    func testCancellationOrBackgroundDuringRecoveryCannotRestartMicrophone() async throws {
        for background in [false, true] {
            let capture = FakeSpeechCapture()
            let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { true })
            controller.requestAndStart(expectedPhrases: [phrase], acceptsSimilarAcknowledgements: false) { XCTFail("Cancelled") }
            capture.permissions[0](true)
            capture.receivers[0](.failure(interruption))
            if background { controller.pauseForBackground() } else { controller.stop() }
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertEqual(capture.starts, 1)
            XCTAssertFalse(controller.isRecovering)
            XCTAssertFalse(controller.isListening)
        }
    }

    @MainActor
    func testNonServiceErrorsAndInactiveAppNeverAutomaticallyRestart() {
        for (error, active) in [(NSError(domain: "OtherDomain", code: 1107), true),
                                (NSError(domain: "kAFAssistantErrorDomain", code: 1700), true),
                                (interruption, false)] {
            let capture = FakeSpeechCapture()
            let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { active })
            controller.requestAndStart(expectedPhrases: [], acceptsSimilarAcknowledgements: true) { XCTFail("Failed") }
            capture.permissions[0](true)
            capture.receivers[0](.failure(error))
            XCTAssertFalse(controller.isRecovering)
            XCTAssertFalse(controller.isListening)
            XCTAssertNotNil(controller.errorMessage)
        }
    }

    @MainActor
    func testAudioInterruptionAndMediaResetCancelPendingRecovery() async throws {
        let notifications: [(Notification.Name, [AnyHashable: Any]?)] = [
            (AVAudioSession.interruptionNotification, [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]),
            (AVAudioSession.mediaServicesWereResetNotification, nil),
            (AVAudioSession.mediaServicesWereLostNotification, nil)
        ]
        for (name, info) in notifications {
            let capture = FakeSpeechCapture()
            let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { true })
            controller.requestAndStart(expectedPhrases: [], acceptsSimilarAcknowledgements: true) { XCTFail("Interrupted") }
            capture.permissions[0](true)
            capture.receivers[0](.failure(interruption))
            NotificationCenter.default.post(name: name, object: nil, userInfo: info)
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertEqual(capture.starts, 1)
            XCTAssertFalse(controller.isRecovering)
            XCTAssertNotNil(controller.errorMessage)
        }
    }

    @MainActor
    func testInvalidatedServiceAtStartupCanRecover() async {
        let capture = FakeSpeechCapture()
        capture.startError = NSError(domain: "kAFAssistantErrorDomain", code: 1101)
        let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { true })
        var matches = 0
        controller.requestAndStart(expectedPhrases: [phrase], acceptsSimilarAcknowledgements: false) { matches += 1 }
        capture.permissions[0](true)
        XCTAssertTrue(controller.isRecovering)
        capture.startError = nil
        await waitForRecovery(capture)
        capture.receivers.last?(.transcript(phrase, isFinal: true))
        XCTAssertEqual(matches, 1)
    }

    @MainActor
    func testAppBecomingInactiveBeforeReconnectCannotStartMicrophone() async throws {
        let capture = FakeSpeechCapture()
        var active = true
        let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { active })
        controller.requestAndStart(expectedPhrases: [], acceptsSimilarAcknowledgements: true) { XCTFail("Inactive") }
        capture.permissions[0](true)
        capture.receivers[0](.failure(interruption))
        active = false
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(capture.starts, 1)
        XCTAssertFalse(controller.isRecovering)
        XCTAssertNotNil(controller.errorMessage)
    }

    @MainActor
    func testNewRequestDuringRecoveryCancelsScheduledRestart() async throws {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { true })
        controller.requestAndStart(expectedPhrases: [], acceptsSimilarAcknowledgements: true) { XCTFail("Replaced") }
        capture.permissions[0](true)
        capture.receivers[0](.failure(interruption))
        var matches = 0
        controller.requestAndStart(expectedPhrases: [phrase], acceptsSimilarAcknowledgements: false) { matches += 1 }
        capture.permissions[1](true)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(capture.starts, 2)
        XCTAssertTrue(controller.isListening)
        capture.receivers[1](.transcript(phrase, isFinal: true))
        XCTAssertEqual(matches, 1)
    }

    @MainActor
    func testAudioInterruptionStopsListeningAndRequiresManualRestart() async throws {
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture, recoveryDelay: 0, isApplicationActive: { true })
        controller.requestAndStart(expectedPhrases: [phrase], acceptsSimilarAcknowledgements: false) { XCTFail("Interrupted") }
        capture.permissions[0](true)
        capture.receivers[0](.transcript(phrase, isFinal: false))
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        XCTAssertFalse(controller.isListening)
        XCTAssertNotNil(controller.errorMessage)
        capture.receivers[0](.failure(interruption))
        capture.receivers[0](.transcript(phrase, isFinal: true))
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(capture.starts, 1)
        XCTAssertFalse(controller.isRecovering)
    }

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
        receive(.failure(NSError(domain: "Cancellation", code: 301)))
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
        capture.receivers[0](.failure(NSError(domain: "OldTask", code: 1107)))
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
