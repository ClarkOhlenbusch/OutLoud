import DeviceActivity
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
        XCTAssertEqual(OnboardingStep.ready.previous, .usageReminders)
        XCTAssertEqual(OnboardingStep.usageReminders.previous, .everyVisit)
        XCTAssertEqual(OnboardingStep.phrase.previous, .apps)
    }

    func testPreviousStepDoesNotMoveBeforeWelcome() {
        XCTAssertEqual(OnboardingStep.welcome.previous, .welcome)
    }

    func testProgressCountExcludesWelcomePage() {
        XCTAssertEqual(OnboardingStep.progressCount, 6)
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

    func testUsageReminderIntervalsHaveStableStoredValues() {
        XCTAssertEqual(UsageReminderInterval(rawValue: 1), .oneMinute)
        XCTAssertEqual(UsageReminderInterval(rawValue: 5), .fiveMinutes)
        XCTAssertEqual(UsageReminderInterval(rawValue: 10), .tenMinutes)
        XCTAssertNil(UsageReminderInterval(rawValue: 3))
    }

    func testUsageReminderActivitiesUseIndependentGenerations() {
        let targetID = UUID()
        let first = UsageReminderActivity.name(targetID: targetID, generation: 1)
        let second = UsageReminderActivity.name(targetID: targetID, generation: 2)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(UsageReminderActivity.isUsageReminder(first))
        XCTAssertFalse(UsageReminderActivity.isUsageReminder(.relockTestActivity))
    }

    func testOneMinuteRemindersUseSingularNotificationCopy() {
        XCTAssertEqual(
            UsageReminderNotification.title(elapsedMinutes: 1, appName: "TikTok"),
            "YOU HAVE SPENT 1 MINUTE ON TIKTOK"
        )
    }

    func testUsageReminderNotificationUsesStrongPluralCopy() {
        XCTAssertEqual(
            UsageReminderNotification.title(elapsedMinutes: 15, appName: "YouTube"),
            "YOU HAVE SPENT 15 MINUTES ON YOUTUBE"
        )
        XCTAssertEqual(
            UsageReminderNotification.body,
            "You asked OutLoud to interrupt you. Close it now."
        )
    }

    func testUsageReminderEventNamesRoundTripElapsedMinutes() {
        let name = UsageReminderEvent.name(for: 25)
        XCTAssertEqual(UsageReminderEvent.elapsedMinutes(from: name), 25)
        XCTAssertNil(
            UsageReminderEvent.elapsedMinutes(from: DeviceActivityEvent.Name("unrelated"))
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

private extension DeviceActivityName {
    static let relockTestActivity = DeviceActivityName("outloud.relock.test")
}
