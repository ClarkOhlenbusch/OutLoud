import DeviceActivity
import FamilyControls
import XCTest
@testable import OutLoud

final class AccessFlowTests: ScreenTimeFlowTestCase {
    @MainActor
    func testRealAcknowledgementReleasesOnlyRequestedAppAndIgnoresLateSpeech() async throws {
        let a = try token(1), b = try token(2)
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [a, b]
        SharedSettings.selection = selection
        SharedSettings.protectionEnabled = true
        SharedSettings.pendingChallenge = .application(a)
        ShieldManager.applySavedSelection()
        let model = AppModel(demoMode: false)
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(capture: capture,
            classify: { await FlexibleAcknowledgementMatcher.evaluate(transcript: $0) },
            isApplicationActive: { true })
        let unlocked = expectation(description: "Real classifier completed the access window")
        controller.requestAndStart(expectedPhrases: model.phrases, acceptsSimilarAcknowledgements: true) {
            XCTAssertTrue(model.completeChallenge())
            unlocked.fulfill()
        }
        capture.permissions[0](true)
        let receive = capture.receivers[0]
        receive(.transcript("This is a bad choice.", isFinal: false))
        XCTAssertEqual(system.shields.applicationTokens, [a, b])
        receive(.transcript("This is a bad choice.", isFinal: true))
        await fulfillment(of: [unlocked], timeout: 20)
        receive(.transcript("This is a bad choice.", isFinal: true))
        XCTAssertEqual(system.starts, 1)
        XCTAssertEqual(system.shields.applicationTokens, [b])
        XCTAssertNil(SharedSettings.pendingChallenge)
        XCTAssertFalse(controller.isListening)
        let window = try XCTUnwrap(SharedSettings.accessWindows.first)
        system.date = window.expiration
        AccessWindowManager.expire(activity: window.activity)
        XCTAssertEqual(system.shields.applicationTokens, [a, b])
    }

    @MainActor
    func testExpirationMatchesScheduleWhenUnlockStartsBetweenWholeSeconds() throws {
        system.date.addTimeInterval(0.75)
        let a = try token(1)
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [a]
        SharedSettings.selection = selection
        SharedSettings.protectionEnabled = true
        let model = AppModel()
        model.pendingChallenge = .application(a)
        XCTAssertTrue(model.completeChallenge())
        let window = try XCTUnwrap(SharedSettings.accessWindows.first)
        let schedule = try XCTUnwrap(system.schedules[window.activity])
        let scheduledEnd = try XCTUnwrap(Calendar.current.date(from: schedule.intervalEnd))
        XCTAssertEqual(window.expiration, scheduledEnd)
        system.date = scheduledEnd
        AccessWindowManager.expire(activity: window.activity)
        XCTAssertEqual(system.shields.applicationTokens, [a])
        XCTAssertTrue(SharedSettings.accessWindows.isEmpty)
    }

    @MainActor
    func testClearingAccessDoesNotStopIndependentReminderMonitors() throws {
        let reminder = UsageReminderActivity.name(targetID: UUID(), generation: 0)
        system.monitors[reminder] = [:]
        let model = AppModel()
        model.pendingChallenge = .application(try token(1))
        XCTAssertTrue(model.completeChallenge())
        XCTAssertEqual(system.monitors.count, 2)
        AccessWindowManager.clear()
        XCTAssertEqual(Set(system.monitors.keys), [reminder])
        XCTAssertTrue(SharedSettings.accessWindows.isEmpty)
    }

    @MainActor
    func testLegacyAndUnrelatedCallbacksCannotRevokeNewWindow() throws {
        let a = try token(1)
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [a]
        SharedSettings.selection = selection
        SharedSettings.protectionEnabled = true
        let model = AppModel()
        model.pendingChallenge = .application(a)
        XCTAssertTrue(model.completeChallenge())
        AccessWindowManager.expire(activity: SharedSettings.relockActivity)
        XCTAssertTrue(system.shields.applicationTokens.isEmpty)
        XCTAssertEqual(SharedSettings.accessWindows.count, 1)
        system.date.addTimeInterval(900)
        AccessWindowManager.expire(activity: DeviceActivityName("unrelated"))
        XCTAssertEqual(SharedSettings.accessWindows.count, 1)
        AppModel().refreshPendingChallenge()
        XCTAssertTrue(SharedSettings.accessWindows.isEmpty)
        XCTAssertEqual(system.shields.applicationTokens, [a])
    }

    @MainActor
    func testTwoAppsKeepIndependentWindowsAndExpirationRestoresOnlyDueApp() throws {
        let a = try token(1), b = try token(2)
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [a, b]
        SharedSettings.selection = selection
        SharedSettings.protectionEnabled = true
        let model = AppModel()
        ShieldManager.applySavedSelection()
        XCTAssertEqual(system.shields.applicationTokens, [a, b])

        model.pendingChallenge = .application(a)
        XCTAssertTrue(model.completeChallenge())
        let first = try XCTUnwrap(SharedSettings.accessWindows.first)
        XCTAssertEqual(system.shields.applicationTokens, [b])
        system.date.addTimeInterval(300)
        model.pendingChallenge = .application(b)
        XCTAssertTrue(model.completeChallenge())
        XCTAssertTrue(system.shields.applicationTokens.isEmpty)
        XCTAssertEqual(SharedSettings.accessWindows.count, 2)
        XCTAssertNotNil(system.monitors[first.activity])

        system.date = first.expiration
        AccessWindowManager.expire(activity: first.activity)
        XCTAssertEqual(system.shields.applicationTokens, [a])
        XCTAssertEqual(SharedSettings.accessWindows.count, 1)
        system.date.addTimeInterval(300)
        model.refreshPendingChallenge()
        XCTAssertEqual(system.shields.applicationTokens, [a, b])
        XCTAssertTrue(system.monitors.isEmpty)
    }

    @MainActor
    func testFailedSecondUnlockDoesNotRevokeFirstApp() throws {
        let a = try token(1), b = try token(2)
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [a, b]
        SharedSettings.selection = selection
        SharedSettings.protectionEnabled = true
        let model = AppModel()
        model.pendingChallenge = .application(a)
        XCTAssertTrue(model.completeChallenge())
        let windows = SharedSettings.accessWindows
        system.failuresRemaining = 2
        model.pendingChallenge = .application(b)
        XCTAssertFalse(model.completeChallenge())
        XCTAssertFalse(model.completeChallenge())
        XCTAssertEqual(SharedSettings.accessWindows, windows)
        XCTAssertEqual(system.shields.applicationTokens, [b])
        XCTAssertNotNil(model.challengeErrorMessage)
        XCTAssertTrue(model.completeChallenge())
        XCTAssertNil(model.challengeErrorMessage)
        XCTAssertTrue(system.shields.applicationTokens.isEmpty)
    }

    @MainActor
    func testStaleExpirationCannotCloseReplacementWindow() throws {
        let a = try token(1)
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [a]
        SharedSettings.selection = selection
        SharedSettings.protectionEnabled = true
        let model = AppModel()
        model.pendingChallenge = .application(a)
        XCTAssertTrue(model.completeChallenge())
        let old = try XCTUnwrap(SharedSettings.accessWindows.first)
        system.date.addTimeInterval(300)
        XCTAssertTrue(model.completeChallenge())
        XCTAssertNil(system.monitors[old.activity])
        system.date = old.expiration
        AccessWindowManager.expire(activity: old.activity)
        XCTAssertTrue(system.shields.applicationTokens.isEmpty)
        XCTAssertEqual(SharedSettings.accessWindows.count, 1)
    }

    @MainActor
    func testPracticeAndCancellationNeverScheduleOrRelease() throws {
        let a = try token(1)
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [a]
        SharedSettings.selection = selection
        SharedSettings.protectionEnabled = true
        ShieldManager.applySavedSelection()
        let model = AppModel()
        model.beginPractice()
        XCTAssertTrue(model.completeChallenge())
        XCTAssertEqual(system.starts, 0)
        XCTAssertEqual(system.shields.applicationTokens, [a])
        SharedSettings.pendingChallenge = .application(a)
        model.refreshPendingChallenge()
        model.cancelChallenge()
        XCTAssertFalse(model.completeChallenge())
        XCTAssertNil(SharedSettings.pendingChallenge)
        XCTAssertFalse(SharedSettings.challengeRequested)
        XCTAssertEqual(system.starts, 0)
    }

    @MainActor
    func testPendingChallengeSurvivesRelaunchAndCancellationClearsFailure() throws {
        let a = try token(1)
        SharedSettings.pendingChallenge = .application(a)
        let id = SharedSettings.challengeRequestID
        let model = AppModel()
        XCTAssertEqual(model.pendingChallenge, .application(a))
        XCTAssertEqual(model.challengeSessionID, id)
        system.failuresRemaining = 1
        XCTAssertFalse(model.completeChallenge())
        let relaunched = AppModel()
        XCTAssertEqual(relaunched.pendingChallenge, .application(a))
        XCTAssertEqual(relaunched.challengeSessionID, id)
        model.cancelChallenge()
        XCTAssertNil(model.challengeErrorMessage)
        XCTAssertNil(AppModel().pendingChallenge)
    }

    @MainActor
    func testNewChallengeDoesNotInheritPreviousUnlockError() throws {
        let a = try token(1), b = try token(2)
        SharedSettings.pendingChallenge = .application(a)
        let model = AppModel()
        system.failuresRemaining = 1
        XCTAssertFalse(model.completeChallenge())
        SharedSettings.pendingChallenge = .application(b)
        model.refreshPendingChallenge()
        XCTAssertNil(model.challengeErrorMessage)
        XCTAssertEqual(model.pendingChallenge, .application(b))
    }

    @MainActor
    func testEveryVisitRearmsButTimerModeAndDisabledProtectionDoNot() throws {
        let a = try token(1)
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [a]
        SharedSettings.selection = selection
        SharedSettings.protectionEnabled = true
        let model = AppModel()
        model.pendingChallenge = .application(a)
        XCTAssertTrue(model.completeChallenge())
        SharedSettings.askAgainMode = .afterTime
        ShieldManager.rearmProtection()
        XCTAssertTrue(system.shields.applicationTokens.isEmpty)
        XCTAssertEqual(SharedSettings.accessWindows.count, 1)
        SharedSettings.askAgainMode = .everyVisit
        ShieldManager.rearmProtection()
        XCTAssertEqual(system.shields.applicationTokens, [a])
        XCTAssertTrue(system.monitors.isEmpty)
        SharedSettings.protectionEnabled = false
        ShieldManager.applySavedSelection()
        AccessWindowManager.expire()
        XCTAssertTrue(system.shields.applicationTokens.isEmpty)
    }

    @MainActor
    func testManualAndAutomaticMappingsPersistAndArePruned() throws {
        let a = try token(1), b = try token(2)
        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [a, b]
        model.saveSelection()
        XCTAssertNil(model.returnDestination(for: a))
        model.setReturnDestination(.youTube, for: a)
        model.pendingChallenge = .application(a)
        XCTAssertEqual(model.returnDestinationForPendingChallenge(), .youTube)
        model.pendingChallenge = .application(b)
        XCTAssertNil(model.returnDestinationForPendingChallenge())
        XCTAssertEqual(AppModel().returnDestination(for: a), .youTube)
        model.setReturnDestination(nil, for: a)
        XCTAssertNil(AppModel().returnDestination(for: a))
        model.setReturnDestination(.youTube, for: a)
        model.selection.applicationTokens = [b]
        model.saveSelection()
        XCTAssertTrue(SharedSettings.returnMappings.isEmpty)
    }
}
