import DeviceActivity
import FamilyControls
import XCTest
@testable import OutLoud

final class OnboardingStepTests: ScreenTimeFlowTestCase {
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

    func testChallengeModesHaveStableStoredValues() {
        XCTAssertEqual(ChallengeMode(rawValue: "speak"), .speak)
        XCTAssertEqual(ChallengeMode(rawValue: "type"), .type)
        XCTAssertEqual(ChallengeMode(rawValue: "either"), .either)
        XCTAssertNil(ChallengeMode(rawValue: "unknown"))

        XCTAssertEqual(ChallengeMode.speak.title, "Say out loud")
        XCTAssertEqual(ChallengeMode.type.title, "Type")
        XCTAssertEqual(ChallengeMode.either.title, "Say or type")
    }

    @MainActor
    func testChallengeModeDefaultsAndPersistence() {
        XCTAssertEqual(SharedSettings.challengeMode, .speak)
        let model = AppModel()
        XCTAssertEqual(model.challengeMode, .speak)

        model.setChallengeMode(.type)
        XCTAssertEqual(model.challengeMode, .type)
        XCTAssertEqual(SharedSettings.challengeMode, .type)

        model.setChallengeMode(.either)
        XCTAssertEqual(model.challengeMode, .either)
        XCTAssertEqual(SharedSettings.challengeMode, .either)

        model.setChallengeMode(.speak)
        XCTAssertEqual(model.challengeMode, .speak)
        XCTAssertEqual(SharedSettings.challengeMode, .speak)
    }

    @MainActor
    func testChallengeModeSummariesReflectSelectedOptions() {
        let model = AppModel()
        model.setAcceptsSimilarAcknowledgements(true)
        model.setChallengeMode(.speak)
        XCTAssertEqual(model.responseStyleSummary, "Own words")
        XCTAssertEqual(model.phraseSummary, "Say out loud · Own words")

        model.setChallengeMode(.type)
        XCTAssertEqual(model.phraseSummary, "Type · Own words")

        model.setChallengeMode(.either)
        XCTAssertEqual(model.phraseSummary, "Say or type · Own words")

        model.setAcceptsSimilarAcknowledgements(false)
        model.phrase = "I am making a bad choice"
        model.setChallengeMode(.type)
        XCTAssertEqual(model.responseStyleSummary, "1 phrase")
        XCTAssertEqual(model.phraseSummary, "Type · 1 phrase")

        model.setChallengeMode(.either)
        XCTAssertEqual(model.phraseSummary, "Say or type · 1 phrase")
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

    func testUsageReminderIntervalsAdvanceToTheNextDailyMultiple() {
        XCTAssertEqual(UsageReminderInterval.oneMinute.nextNotificationMinute(after: 72), 73)
        XCTAssertEqual(UsageReminderInterval.fiveMinutes.nextNotificationMinute(after: 73), 75)
        XCTAssertEqual(UsageReminderInterval.fiveMinutes.nextNotificationMinute(after: 75), 80)
        XCTAssertEqual(UsageReminderInterval.tenMinutes.nextNotificationMinute(after: 73), 80)
    }

    func testChangingReminderCadenceAcceptsTheNextScheduledMilestone() {
        // Five minutes already reported; switching to ten must accept ten,
        // not wait for an unscheduled fifteen-minute event.
        XCTAssertTrue(UsageReminderEvent.isExpected(10, after: 5, interval: .tenMinutes))
        XCTAssertFalse(UsageReminderEvent.isExpected(15, after: 5, interval: .tenMinutes))
        XCTAssertTrue(UsageReminderEvent.isExpected(20, after: 10, interval: .tenMinutes))
        XCTAssertTrue(UsageReminderEvent.isExpected(5, after: 3, interval: .fiveMinutes))
        XCTAssertTrue(UsageReminderEvent.isExpected(11, after: 10, interval: .oneMinute))
        XCTAssertFalse(UsageReminderEvent.isExpected(10, after: 10, interval: .tenMinutes))
    }

    @MainActor
    func testFailedUnlockPreservesChallengeAndCanRetry() {
        SharedSettings.pendingChallenge = .selection
        let model = AppModel()
        let requestID = model.challengeSessionID
        system.failuresRemaining = 1
        let failed = model.completeChallenge()
        XCTAssertFalse(failed)
        XCTAssertNotNil(model.challengeErrorMessage)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.pendingChallenge, .selection)
        XCTAssertEqual(SharedSettings.pendingChallenge, .selection)
        XCTAssertNil(SharedSettings.unlockExpiration)

        // Returning to OutLoud must keep the same failed challenge and retry UI.
        model.refreshPendingChallenge()
        XCTAssertEqual(model.challengeSessionID, requestID)
        XCTAssertNotNil(model.challengeErrorMessage)

        XCTAssertTrue(model.completeChallenge())
        XCTAssertNil(model.challengeErrorMessage)
        XCTAssertNil(SharedSettings.pendingChallenge)
        XCTAssertEqual(SharedSettings.accessWindows.count, 1)
        model.dismissChallenge()
        XCTAssertNil(model.pendingChallenge)
    }

    func testStandardAuthorizationGrantsScreenTimeAccess() {
        XCTAssertTrue(AuthorizationStatus.approved.grantsOutLoudScreenTimeAccess)
        XCTAssertFalse(AuthorizationStatus.denied.grantsOutLoudScreenTimeAccess)
        XCTAssertFalse(AuthorizationStatus.notDetermined.grantsOutLoudScreenTimeAccess)
    }

#if compiler(>=6.3)
    @available(iOS 26.4, *)
    func testDataAccessAuthorizationAlsoGrantsScreenTimeAccess() {
        XCTAssertTrue(AuthorizationStatus.approvedWithDataAccess.grantsOutLoudScreenTimeAccess)
    }
#endif

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
