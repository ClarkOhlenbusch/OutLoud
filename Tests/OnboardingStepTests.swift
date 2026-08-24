import XCTest
@testable import OutLoud

final class OnboardingStepTests: XCTestCase {
    func testStoredValuesRestoreEveryStep() {
        for step in OnboardingStep.allCases {
            XCTAssertEqual(OnboardingStep(storedValue: step.rawValue), step)
        }
    }

    func testInvalidStoredValueStartsAtWelcome() {
        XCTAssertEqual(OnboardingStep(storedValue: -1), .welcome)
        XCTAssertEqual(OnboardingStep(storedValue: 999), .welcome)
    }

    func testPreviousStepMovesBackOnePage() {
        XCTAssertEqual(OnboardingStep.ready.previous, .everyVisit)
        XCTAssertEqual(OnboardingStep.phrase.previous, .apps)
    }

    func testPreviousStepDoesNotMoveBeforeWelcome() {
        XCTAssertEqual(OnboardingStep.welcome.previous, .welcome)
    }

    func testProgressCountExcludesWelcomePage() {
        XCTAssertEqual(OnboardingStep.progressCount, 5)
    }

    func testAskAgainModesHaveStableStoredValues() {
        XCTAssertEqual(AskAgainMode(rawValue: "everyVisit"), .everyVisit)
        XCTAssertEqual(AskAgainMode(rawValue: "afterTime"), .afterTime)
        XCTAssertNil(AskAgainMode(rawValue: "unknown"))
    }

    func testEveryVisitUsesFifteenMinuteFallbackWindow() {
        XCTAssertEqual(
            AskAgainMode.everyVisit.accessWindowDuration(timerDuration: 60 * 60),
            15 * 60
        )
    }

    func testTimerModeUsesSelectedWindow() {
        XCTAssertEqual(
            AskAgainMode.afterTime.accessWindowDuration(timerDuration: 30 * 60),
            30 * 60
        )
    }

    func testEveryReturnDestinationHasAnAppLinkAndUniversalLink() {
        for destination in ReturnDestination.allCases {
            XCTAssertEqual(destination.launchURLs.count, 2)
            XCTAssertNotEqual(destination.launchURLs[0].scheme, "https")
            XCTAssertEqual(destination.launchURLs[1].scheme, "https")
        }
    }

    func testReturnDestinationDisplayNamesAreUnique() {
        let names = ReturnDestination.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
    }
}
