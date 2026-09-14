import XCTest
@testable import OutLoud

final class TypedChallengeTests: XCTestCase {
    @MainActor
    func testCancelledCheckCannotAcceptOrOverwriteANewerAttempt() async {
        var replies: [CheckedContinuation<AcknowledgementMatch, Never>] = []
        let firstStarted = expectation(description: "First request started")
        let started = expectation(description: "Both requests started")
        started.expectedFulfillmentCount = 2
        let controller = TypedChallengeController(classify: { _ in
            await withCheckedContinuation { continuation in
                replies.append(continuation)
                if replies.count == 1 { firstStarted.fulfill() }
                started.fulfill()
            }
        })
        var accepted = 0
        let rejected = expectation(description: "Current request rejected")
        controller.submit("A new acknowledgment", phrases: [], acceptsSimilar: true,
                          onMatch: { accepted += 1 }, onReject: { XCTFail("Stale rejection") })
        // Let the first request enter its non-cancellable inference work.
        await fulfillment(of: [firstStarted], timeout: 2)
        controller.cancel()
        controller.submit("Another acknowledgment", phrases: [], acceptsSimilar: true,
                          onMatch: { accepted += 1 }, onReject: { rejected.fulfill() })
        await fulfillment(of: [started], timeout: 2)
        replies[0].resume(returning: .accepted)
        replies[1].resume(returning: .rejected)
        await fulfillment(of: [rejected], timeout: 2)
        XCTAssertEqual(accepted, 0)
        XCTAssertFalse(controller.isChecking)
        XCTAssertNotNil(controller.errorMessage)
    }

    @MainActor
    func testTimeoutAllowsRetryAndIgnoresLateAcceptance() async {
        var reply: CheckedContinuation<AcknowledgementMatch, Never>?
        let started = expectation(description: "Inference started")
        let controller = TypedChallengeController(classify: { _ in
            await withCheckedContinuation { continuation in
                reply = continuation
                started.fulfill()
            }
        }, timeout: 20_000_000)
        var accepted = 0
        controller.submit("A new acknowledgment", phrases: [], acceptsSimilar: true,
                          onMatch: { accepted += 1 }, onReject: {})
        await fulfillment(of: [started], timeout: 2)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(controller.isChecking)
        XCTAssertTrue(controller.errorMessage?.contains("too long") == true)
        reply?.resume(returning: .accepted)
        controller.submit("My phrase", phrases: ["My phrase"], acceptsSimilar: false,
                          onMatch: { accepted += 1 }, onReject: { XCTFail() })
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(accepted, 1)
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    func testTypedSpecificPhraseAndQuestionUseTheProductionController() {
        let controller = TypedChallengeController(classify: { _ in XCTFail("Unexpected inference"); return .accepted })
        var accepted = 0, rejected = 0
        controller.submit("My phrase?", phrases: ["My phrase"], acceptsSimilar: false,
                          onMatch: { accepted += 1 }, onReject: { rejected += 1 })
        XCTAssertEqual(accepted, 0)
        XCTAssertEqual(rejected, 1)
        controller.submit("My phrase.", phrases: ["My phrase"], acceptsSimilar: false,
                          onMatch: { accepted += 1 }, onReject: { rejected += 1 })
        XCTAssertEqual(accepted, 1)
        XCTAssertNil(controller.errorMessage)
    }
}
