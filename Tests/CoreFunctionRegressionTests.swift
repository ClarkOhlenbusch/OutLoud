import Combine
import FamilyControls
import ManagedSettings
import UserNotifications
import XCTest
@testable import OutLoud

final class CoreFunctionRegressionTests: ScreenTimeFlowTestCase {
    @MainActor
    func testRevocationUpdatesLiveStatusAndDiscardsInvalidTokensAndWindows() throws {
        let a = try token(1)
        SharedSettings.selection.applicationTokens = [a]
        SharedSettings.protectionEnabled = true
        SharedSettings.pendingChallenge = .application(a)
        var receive: ((AuthorizationStatus) -> Void)?
        ScreenTimeAuthorizationClient.current.observe = { callback in
            receive = callback
            return AnyCancellable {}
        }
        let model = AppModel(demoMode: false)
        XCTAssertTrue(model.completeChallenge())
        model.setReturnDestination(.youTube, for: a)
        receive?(.denied)

        XCTAssertFalse(model.isProtectionActive)
        XCTAssertFalse(model.protectionEnabled)
        XCTAssertFalse(SharedSettings.protectionEnabled)
        XCTAssertEqual(model.selection.selectedItemCount, 0)
        XCTAssertEqual(SharedSettings.selection.selectedItemCount, 0)
        XCTAssertTrue(SharedSettings.returnMappings.isEmpty)
        XCTAssertTrue(SharedSettings.accessWindows.isEmpty)
        XCTAssertNil(model.pendingChallenge)
        XCTAssertTrue(system.monitors.isEmpty)
        XCTAssertEqual(system.shields.selectedItemCount, 0)
    }

    @MainActor
    func testRestoringPermissionRequiresFreshSelectionBeforeProtectionCanTurnOn() async throws {
        var status = AuthorizationStatus.denied
        var requests = 0
        ScreenTimeAuthorizationClient.current.status = { status }
        ScreenTimeAuthorizationClient.current.request = { requests += 1; status = .approved }
        NotificationPermissionClient.requiresFallback = { false }
        SharedSettings.selection.applicationTokens = [try token(1)]
        let model = AppModel(demoMode: false)
        await model.enableProtectionWithAuthorizationCheck()
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(model.isAuthorized)
        XCTAssertFalse(model.protectionEnabled)
        XCTAssertEqual(model.selection.selectedItemCount, 0)
        XCTAssertNotNil(model.errorMessage)

        model.selection.applicationTokens = [try token(2)]
        model.saveSelection()
        await model.enableProtectionWithAuthorizationCheck()
        XCTAssertTrue(model.isProtectionActive)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(system.shields.applicationTokens, [try token(2)])
    }

    @MainActor
    func testFailedScreenTimeRequestCannotFinishOnboardingOrEnableProtection() async throws {
        ScreenTimeAuthorizationClient.current.status = { .denied }
        ScreenTimeAuthorizationClient.current.request = { throw FamilyControlsError.authorizationCanceled }
        NotificationPermissionClient.requiresFallback = { false }
        let model = AppModel(demoMode: false)
        await model.enableProtectionWithAuthorizationCheck()
        XCTAssertFalse(model.protectionEnabled)
        await model.finishOnboarding()
        XCTAssertFalse(model.onboardingCompleted)
        XCTAssertFalse(SharedSettings.onboardingCompleted)
        XCTAssertEqual(system.shields.selectedItemCount, 0)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testUndeterminedAuthorizationNeverReportsActiveProtection() {
        SharedSettings.protectionEnabled = true
        ScreenTimeAuthorizationClient.current.status = { .notDetermined }
        let model = AppModel(demoMode: false)
        XCTAssertFalse(model.isProtectionActive)
    }

    @MainActor
    func testDelayedAuthorizationRestoresShieldsWithoutHonoringLegacyBroadWindows() throws {
        let a = try token(1)
        SharedSettings.selection.applicationTokens = [a]
        SharedSettings.protectionEnabled = true
        SharedSettings.accessWindows = [AccessWindow(id: UUID(), challenge: .selection,
            expiration: system.date.addingTimeInterval(900))]
        ScreenTimeAuthorizationClient.current.status = { .notDetermined }
        var receive: ((AuthorizationStatus) -> Void)?
        ScreenTimeAuthorizationClient.current.observe = { callback in
            receive = callback
            return AnyCancellable {}
        }
        let model = AppModel(demoMode: false)
        XCTAssertFalse(model.isProtectionActive)
        receive?(.approved)
        XCTAssertTrue(model.isProtectionActive)
        XCTAssertEqual(system.shields.applicationTokens, [a])
    }

    @MainActor
    func testEveryVisitRequiresConfirmationAndLegacyUnconfirmedSettingsUseTimer() {
        XCTAssertEqual(SharedSettings.askAgainMode, .afterTime)
        SharedSettings.defaults.set("everyVisit", forKey: "askAgainMode")
        let model = AppModel()
        XCTAssertEqual(model.askAgainMode, .afterTime)
        XCTAssertTrue(SharedSettings.needsEveryVisitSetup)
        model.setAskAgainMode(.everyVisit)
        XCTAssertEqual(model.askAgainMode, .afterTime)
        model.confirmEveryVisitAutomation()
        XCTAssertFalse(SharedSettings.needsEveryVisitSetup)
        XCTAssertEqual(model.askAgainMode, .everyVisit)
        XCTAssertEqual(AppModel().askAgainMode, .everyVisit)
        model.setAskAgainMode(.afterTime)
        XCTAssertEqual(AppModel().askAgainMode, .afterTime)
    }

    @MainActor
    func testLegacyDefaultGetsSetupNoticeButNewTimerOnboardingDoesNot() async {
        SharedSettings.onboardingCompleted = true
        XCTAssertEqual(SharedSettings.askAgainMode, .afterTime)
        XCTAssertTrue(SharedSettings.needsEveryVisitSetup)

        SharedSettings.onboardingCompleted = false
        let model = AppModel(demoMode: true)
        await model.finishOnboarding(enableProtection: false)
        XCTAssertEqual(SharedSettings.askAgainMode, .afterTime)
        XCTAssertFalse(SharedSettings.needsEveryVisitSetup)
    }

    @MainActor
    func testChangingSelectedAppsRequiresUpdatingTheEveryVisitAutomation() throws {
        SharedSettings.selection.applicationTokens = [try token(1)]
        let model = AppModel(demoMode: false)
        model.confirmEveryVisitAutomation()
        model.selection.applicationTokens.insert(try token(2))
        model.saveSelection()
        XCTAssertEqual(model.askAgainMode, .afterTime)
        XCTAssertFalse(SharedSettings.everyVisitAutomationConfirmed)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testBroadSelectionsAreRejectedWithoutChangingExistingProtection() throws {
        let a = try token(1)
        SharedSettings.selection.applicationTokens = [a]
        SharedSettings.protectionEnabled = true
        let model = AppModel(demoMode: false)
        ShieldManager.applySavedSelection()
        model.selection.categoryTokens = [try categoryToken()]
        model.saveSelection()
        XCTAssertTrue(model.selection.categoryTokens.isEmpty)
        XCTAssertTrue(SharedSettings.selection.categoryTokens.isEmpty)
        XCTAssertEqual(system.shields.applicationTokens, [a])
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testCategoryAndUnresolvedChallengesNeverReleaseTheWholeSelection() throws {
        let a = try token(1), b = try token(2), category = try categoryToken()
        SharedSettings.selection.applicationTokens = [a, b]
        SharedSettings.selection.categoryTokens = [category]
        SharedSettings.protectionEnabled = true
        let model = AppModel(demoMode: false)
        for challenge in [PendingChallenge.category(category), .selection] {
            model.pendingChallenge = challenge
            XCTAssertNotNil(model.challengeRecoveryMessage)
            XCTAssertFalse(model.completeChallenge())
            // An upgrade must also stop honoring broad windows saved by older builds.
            SharedSettings.accessWindows = [AccessWindow(id: UUID(), challenge: challenge,
                expiration: system.date.addingTimeInterval(900))]
            ShieldManager.applySavedSelection()
            XCTAssertEqual(system.shields.applicationTokens, [a, b])
            XCTAssertEqual(system.shields.categoryTokens, [category])
        }
        XCTAssertEqual(system.starts, 0)
    }

    @MainActor
    func testOldChallengeResultCannotUnlockANewerChallenge() throws {
        let a = try token(1), b = try token(2)
        SharedSettings.selection.applicationTokens = [a, b]
        SharedSettings.protectionEnabled = true
        SharedSettings.pendingChallenge = .application(a)
        let model = AppModel(demoMode: false)
        let previousID = model.challengeSessionID
        model.cancelChallenge()
        SharedSettings.pendingChallenge = .application(b)
        model.refreshPendingChallenge()
        XCTAssertFalse(model.completeChallenge(expectedSessionID: previousID))
        XCTAssertTrue(SharedSettings.accessWindows.isEmpty)
        XCTAssertEqual(system.shields.applicationTokens, [a, b])
        XCTAssertTrue(model.completeChallenge(expectedSessionID: model.challengeSessionID))
        XCTAssertEqual(system.shields.applicationTokens, [a])
    }

    @MainActor
    func testLockNotificationClosesTimedWindowsAndWorksWithProtectionOff() async throws {
        let a = try token(1), b = try token(2)
        SharedSettings.selection.applicationTokens = [a, b]
        SharedSettings.protectionEnabled = true
        SharedSettings.askAgainMode = .afterTime
        NotificationPermissionClient.requiresFallback = { false }
        let model = AppModel(demoMode: false)
        model.pendingChallenge = .application(a)
        XCTAssertTrue(model.completeChallenge())
        await AppDelegate.performNotificationAction(identifier: UsageReminderNotification.identifier,
            actionIdentifier: UsageReminderNotification.lockActionIdentifier)
        XCTAssertTrue(SharedSettings.accessWindows.isEmpty)
        XCTAssertEqual(system.shields.applicationTokens, [a, b])

        model.setProtection(false)
        XCTAssertEqual(system.shields.selectedItemCount, 0)
        await AppDelegate.performNotificationAction(identifier: UsageReminderNotification.identifier,
            actionIdentifier: UsageReminderNotification.lockActionIdentifier)
        model.refreshAfterProtectionAction(error: nil)
        XCTAssertTrue(model.isProtectionActive)
        XCTAssertNil(model.pendingChallenge)
        XCTAssertEqual(system.shields.applicationTokens, [a, b])
    }

    @MainActor
    func testPermissionRevokedDuringNotificationPromptCannotFinishSetup() async throws {
        var status = AuthorizationStatus.approved
        ScreenTimeAuthorizationClient.current.status = { status }
        NotificationPermissionClient.requiresFallback = { true }
        NotificationPermissionClient.request = { status = .denied; return true }
        SharedSettings.selection.applicationTokens = [try token(1)]
        let model = AppModel(demoMode: false)
        await model.finishOnboarding()
        XCTAssertFalse(model.onboardingCompleted)
        XCTAssertFalse(model.isProtectionActive)
        XCTAssertEqual(SharedSettings.selection.selectedItemCount, 0)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testIndividualWebsiteUnlockLeavesOtherItemsProtected() throws {
        let website = try JSONDecoder().decode(WebDomainToken.self,
            from: JSONEncoder().encode(["data": Data([4])]))
        let otherWebsite = try JSONDecoder().decode(WebDomainToken.self,
            from: JSONEncoder().encode(["data": Data([5])]))
        SharedSettings.selection.applicationTokens = [try token(1)]
        SharedSettings.selection.webDomainTokens = [website, otherWebsite]
        SharedSettings.protectionEnabled = true
        let model = AppModel(demoMode: false)
        model.pendingChallenge = .webDomain(website)
        XCTAssertTrue(model.completeChallenge())
        XCTAssertEqual(system.shields.webDomainTokens, [otherWebsite])
        XCTAssertEqual(system.shields.applicationTokens, [try token(1)])
        let window = try XCTUnwrap(SharedSettings.accessWindows.first)
        system.date = window.expiration
        AccessWindowManager.expire(activity: window.activity)
        XCTAssertEqual(system.shields.webDomainTokens, [website, otherWebsite])
    }

    @MainActor
    func testNotificationBodyAndDismissActionsNeverChangeProtection() async throws {
        SharedSettings.selection.applicationTokens = [try token(1)]
        NotificationPermissionClient.requiresFallback = { false }
        for identifier in [UsageReminderNotification.identifier, ProtectionReminderNotification.identifier(for: 3600)] {
            for action in [UNNotificationDefaultActionIdentifier, UNNotificationDismissActionIdentifier] {
                await AppDelegate.performNotificationAction(identifier: identifier, actionIdentifier: action)
                XCTAssertFalse(SharedSettings.protectionEnabled)
                XCTAssertEqual(system.shields.selectedItemCount, 0)
            }
        }
    }

    @MainActor
    func testNotificationActionCannotBypassDeniedPermission() async throws {
        SharedSettings.selection.applicationTokens = [try token(1)]
        ScreenTimeAuthorizationClient.current.status = { .denied }
        ScreenTimeAuthorizationClient.current.request = { throw FamilyControlsError.authorizationCanceled }
        await AppDelegate.performNotificationAction(identifier: UsageReminderNotification.identifier,
            actionIdentifier: UsageReminderNotification.lockActionIdentifier)
        XCTAssertFalse(SharedSettings.protectionEnabled)
        XCTAssertEqual(system.shields.selectedItemCount, 0)
    }

    private func categoryToken() throws -> ActivityCategoryToken {
        try JSONDecoder().decode(ActivityCategoryToken.self,
            from: JSONEncoder().encode(["data": Data([3])]))
    }
}
