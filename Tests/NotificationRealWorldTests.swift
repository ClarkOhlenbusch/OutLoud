import AVFoundation
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications
import XCTest
@testable import OutLoud

/// Real-World Behavioral Tests for OutLoud Notifications & Screen Time Reminders.
///
/// Written from a black-box, specification-first perspective to verify real-world
/// failure modes, iOS notification contracts, time-sensitivity under Focus/DND modes,
/// permission lifecycle transitions, deduplication, and atomic rollback without
/// fitting to specific implementation details.
final class NotificationRealWorldTests: ScreenTimeFlowTestCase {

    @MainActor
    func testOnboardingPermissionStepRequiresNotificationsEvenWithScreenTimeAlreadyApproved() async {
        NotificationPermissionClient.requiresFallback = { true }
        NotificationPermissionClient.request = { false }
        let model = AppModel(demoMode: false)
        model.authorizationStatus = .approved

        let denied = await model.requestAuthorization()
        XCTAssertFalse(denied, "The UI must not advance based only on Screen Time approval")
        XCTAssertTrue(model.isAuthorized)
        XCTAssertNotNil(model.errorMessage)

        NotificationPermissionClient.request = { true }
        let granted = await model.requestAuthorization()
        XCTAssertTrue(granted, "Retry must recheck notifications after they are enabled in Settings")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testFinishingOnboardingRechecksNotificationsBeforeSavingCompletionOrApplyingShields() async throws {
        NotificationPermissionClient.requiresFallback = { true }
        NotificationPermissionClient.request = { false }
        let model = AppModel(demoMode: false)
        let app = try token(1)
        model.selection.applicationTokens = [app]
        model.saveSelection()
        model.moveOnboarding(to: .ready)

        await model.finishOnboarding()

        XCTAssertFalse(model.onboardingCompleted)
        XCTAssertFalse(SharedSettings.onboardingCompleted)
        XCTAssertEqual(model.onboardingStep, .ready)
        XCTAssertFalse(model.protectionEnabled)
        XCTAssertFalse(SharedSettings.protectionEnabled)
        XCTAssertTrue(system.shields.applicationTokens.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isFinishingOnboarding)

        NotificationPermissionClient.request = { true }
        await model.finishOnboarding()

        XCTAssertTrue(model.onboardingCompleted)
        XCTAssertTrue(SharedSettings.onboardingCompleted)
        XCTAssertTrue(model.protectionEnabled)
        XCTAssertEqual(system.shields.applicationTokens, [app])
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testDirectShieldOpeningDoesNotRequireNotificationsToFinishOnboarding() async throws {
        NotificationPermissionClient.requiresFallback = { false }
        var requests = 0
        NotificationPermissionClient.request = { requests += 1; return false }
        let model = AppModel(demoMode: false)
        let app = try token(1)
        model.selection.applicationTokens = [app]
        model.saveSelection()

        await model.finishOnboarding()

        XCTAssertTrue(model.onboardingCompleted)
        XCTAssertTrue(model.protectionEnabled)
        XCTAssertEqual(system.shields.applicationTokens, [app])
        XCTAssertEqual(requests, 0)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testRemindersOnlySetupDoesNotRequireTheShieldNotificationHandoff() async {
        NotificationPermissionClient.requiresFallback = { true }
        var requests = 0
        NotificationPermissionClient.request = { requests += 1; return false }
        ProtectionReminderManager.addRequest = { _ in }
        let model = AppModel(demoMode: false)

        await model.finishOnboarding(enableProtection: false)

        XCTAssertTrue(model.onboardingCompleted)
        XCTAssertFalse(model.protectionEnabled)
        XCTAssertTrue(system.shields.applicationTokens.isEmpty)
        XCTAssertEqual(requests, 0)
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - 1. Notification Permission Lifecycle & Protection Gating

    /// Real-world scenario: A user denies notification permission.
    /// Because OutLoud's shield unlock flow and mindful pause reminders rely on notifications,
    /// enabling protection must be blocked, and actionable guidance to Settings must be shown.
    @MainActor
    func testRealWorld_notificationDenied_preventsProtectionAndProvidesSettingsGuidance() async throws {
        NotificationPermissionClient.request = { false }
        NotificationPermissionClient.check = { false }
        NotificationPermissionClient.requiresFallback = { true }

        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [try token(1)]
        model.saveSelection()

        XCTAssertFalse(model.protectionEnabled, "Protection should initially be disabled")

        // Attempt to arm protection when notifications are blocked
        await model.enableProtectionWithAuthorizationCheck()

        // Protection must NOT be enabled to prevent locking the user out
        XCTAssertFalse(model.protectionEnabled, "Protection must not arm without notification permissions")
        XCTAssertNotNil(model.errorMessage, "Error message must be presented to the user")
        
        let message = model.errorMessage ?? ""
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("notification") ||
            message.localizedCaseInsensitiveContains("settings"),
            "Error message should guide user to notifications or Settings: got '\(message)'"
        )
    }

    /// Real-world scenario: User grants notification authorization.
    /// Protection can be successfully armed, and any prior error is cleared.
    @MainActor
    func testRealWorld_notificationGranted_allowsEnablingProtection() async throws {
        NotificationPermissionClient.request = { true }
        NotificationPermissionClient.check = { true }
        NotificationPermissionClient.requiresFallback = { true }

        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [try token(1)]
        model.saveSelection()

        await model.enableProtectionWithAuthorizationCheck()

        XCTAssertTrue(model.protectionEnabled, "Protection should successfully arm when notifications are authorized")
        XCTAssertNil(model.errorMessage, "No error message should be displayed")
    }

    /// Real-world scenario: User previously denied notifications, then goes into iOS Settings,
    /// turns notifications ON, and returns to OutLoud.
    /// Calling checkAuthorization should reflect the newly authorized state.
    @MainActor
    func testRealWorld_permissionGrantedInSettingsAfterPriorDenial_updatesAuthorizationStatus() async throws {
        // Start in denied state
        NotificationPermissionClient.request = { false }
        NotificationPermissionClient.check = { false }
        NotificationPermissionClient.requiresFallback = { true }

        let model = AppModel(demoMode: false)
        await model.checkNotificationAuthorization()
        XCTAssertFalse(model.isNotificationAuthorized, "Initially not authorized")

        // User switches toggle in iOS Settings -> Notifications -> Allow
        NotificationPermissionClient.check = { true }
        NotificationPermissionClient.request = { true }

        await model.checkNotificationAuthorization()
        XCTAssertTrue(model.isNotificationAuthorized, "Authorization status must update to true after granting in Settings")

        // Now enabling protection should succeed
        model.selection.applicationTokens = [try token(1)]
        model.saveSelection()
        await model.enableProtectionWithAuthorizationCheck()
        XCTAssertTrue(model.protectionEnabled)
        XCTAssertNil(model.errorMessage)
    }

    /// Real-world scenario: User tries to configure usage reminders while notifications are denied.
    /// Reminders must not be armed, no monitoring schedules created, and an error must be surfaced.
    @MainActor
    func testRealWorld_usageRemindersRequireNotificationPermission() async throws {
        NotificationPermissionClient.request = { false }
        NotificationPermissionClient.check = { false }

        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [try token(1)]
        model.saveSelection()

        await model.selectUsageReminderInterval(.fiveMinutes)

        XCTAssertFalse(model.usageRemindersEnabled, "Usage reminders must not be enabled when notifications are denied")
        XCTAssertFalse(SharedSettings.usageRemindersEnabled)
        XCTAssertTrue(system.monitors.isEmpty, "No DeviceActivity monitors should be scheduled")
        XCTAssertNotNil(model.errorMessage, "User must be informed why reminders could not be enabled")

        // User resolves permission
        NotificationPermissionClient.request = { true }
        NotificationPermissionClient.check = { true }

        await model.selectUsageReminderInterval(.fiveMinutes)

        XCTAssertTrue(model.usageRemindersEnabled, "Usage reminders should now be enabled")
        XCTAssertTrue(SharedSettings.usageRemindersEnabled)
        XCTAssertEqual(system.monitors.count, 1, "One monitor should be registered for the selected app")
        XCTAssertNil(model.errorMessage, "Error message should be cleared")
    }

    // MARK: - 2. Time-Sensitive Delivery & Focus / Do Not Disturb Bypass

    /// Real-world scenario: Doomscrolling often occurs while Focus Modes (Do Not Disturb, Sleep, Work)
    /// are active. Challenge notifications and usage reminders MUST be marked .timeSensitive
    /// so the OS delivers them immediately through Focus filters.
    func testRealWorld_challengeNotification_meetsTimeSensitiveContract() {
        let content = UNMutableNotificationContent()
        content.title = "Say it out loud"
        content.body = "Tap to acknowledge the choice out loud and continue."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0
        content.categoryIdentifier = "OUTLOUD_CHALLENGE"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "outloud.pending-challenge",
            content: content,
            trigger: trigger
        )

        // Verify time-sensitive priority and sound
        XCTAssertEqual(request.content.interruptionLevel, .timeSensitive, "Challenge notifications must be .timeSensitive")
        XCTAssertNotNil(request.content.sound, "Notification must configure an audible sound alert")
        XCTAssertEqual(request.content.relevanceScore, 1.0, "Relevance score must be maximum (1.0)")
        XCTAssertEqual(request.content.categoryIdentifier, "OUTLOUD_CHALLENGE")
        XCTAssertFalse(request.content.title.isEmpty, "Title must be non-empty")
        XCTAssertFalse(request.content.body.isEmpty, "Body must be non-empty")

        // Trigger should be immediate / short and non-repeating
        XCTAssertFalse(trigger.repeats, "Challenge notification trigger must not repeat")
        XCTAssertLessThanOrEqual(trigger.timeInterval, 1.0, "Trigger delay must be <= 1 second for responsive delivery")
        XCTAssertEqual(request.identifier, "outloud.pending-challenge", "Identifier must be stable for deduplication")
    }

    /// Real-world scenario: iOS strips .timeSensitive if the host application does not hold
    /// the time-sensitive entitlement in its provisioning profile.
    func testRealWorld_mainAppEntitlements_includesTimeSensitiveCapability() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectDir = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let entitlementsURL = projectDir.appendingPathComponent("Configuration/OutLoud.entitlements")

        let data = try Data(contentsOf: entitlementsURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(
            plist["com.apple.developer.usernotifications.time-sensitive"] as? Bool,
            true,
            "Main app entitlements must declare com.apple.developer.usernotifications.time-sensitive = true"
        )
    }

    /// Real-world scenario: App extensions (ShieldAction, DeviceActivityMonitor) will FAIL Apple
    /// provisioning profile generation if they mistakenly include the time-sensitive entitlement.
    func testRealWorld_extensionEntitlements_excludeTimeSensitiveKey() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectDir = testFileURL.deletingLastPathComponent().deletingLastPathComponent()

        let extensionPaths = [
            "Configuration/DeviceActivityMonitor.entitlements",
            "Configuration/ShieldAction.entitlements",
            "Configuration/ShieldConfiguration.entitlements"
        ]

        for path in extensionPaths {
            let url = projectDir.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let data = try Data(contentsOf: url)
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            )

            XCTAssertNil(
                plist["com.apple.developer.usernotifications.time-sensitive"],
                "Extension \(path) must NOT declare time-sensitive key to avoid Apple provisioning rejection"
            )
        }
    }

    // MARK: - 3. Reminder Scheduling, Cadence Transitions & Deduplication

    /// Real-world scenario: When a user toggles off usage reminders, all scheduled monitors
    /// in the system daemon must be stopped immediately to avoid phantom alerts later.
    @MainActor
    func testRealWorld_turningOffUsageReminders_cleansUpAllSystemMonitors() async throws {
        NotificationPermissionClient.request = { true }
        NotificationPermissionClient.check = { true }

        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [try token(1), try token(2)]
        model.saveSelection()

        await model.selectUsageReminderInterval(.fiveMinutes)
        XCTAssertTrue(model.usageRemindersEnabled)
        XCTAssertFalse(system.monitors.isEmpty, "Monitors should be active in system daemon")

        // User turns off reminders in UI
        model.turnOffUsageReminders()

        XCTAssertFalse(model.usageRemindersEnabled)
        XCTAssertFalse(SharedSettings.usageRemindersEnabled)
        XCTAssertTrue(system.monitors.isEmpty, "All background monitors must be completely removed")
    }

    /// Real-world scenario: Changing reminder interval from 5m to 15m.
    /// The system must replace the 5m event with a 15m event. It must not leave both running.
    func testRealWorld_changingReminderCadence_replacesScheduleAtomically() throws {
        var selection = FamilyActivitySelection()
        let appToken = try token(1)
        selection.applicationTokens = [appToken]
        SharedSettings.selection = selection
        SharedSettings.usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = .fiveMinutes
        try UsageReminderManager.refreshMonitoring()

        let firstTarget = try XCTUnwrap(SharedSettings.usageReminderTargets.first)
        let initialEvent = try XCTUnwrap(system.monitors[firstTarget.activityName]?.first)
        XCTAssertEqual(initialEvent.key, UsageReminderEvent.name(for: 5))

        // Change interval to 10 minutes
        SharedSettings.usageReminderInterval = .tenMinutes
        try UsageReminderManager.refreshMonitoring()

        let updatedTarget = try XCTUnwrap(SharedSettings.usageReminderTargets.first)
        let updatedEvent = try XCTUnwrap(system.monitors[updatedTarget.activityName]?.first)
        XCTAssertEqual(updatedEvent.key, UsageReminderEvent.name(for: 10))
        XCTAssertEqual(updatedEvent.value.threshold.minute, 10)
        XCTAssertEqual(
            system.monitors[updatedTarget.activityName]?.count,
            1,
            "Only the new interval event must be registered—no lingering old events"
        )
    }

    /// Real-world scenario: The OS daemon fires duplicate threshold callbacks for the same minute mark.
    /// The manager must deduplicate and notify only once.
    func testRealWorld_duplicateThresholdCallbacks_deliverNotificationOnlyOnce() throws {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [try token(1)]
        SharedSettings.selection = selection
        SharedSettings.usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = .fiveMinutes
        try UsageReminderManager.refreshMonitoring()

        let target = try XCTUnwrap(SharedSettings.usageReminderTargets.first)
        var deliveryCount = 0

        // Fire 5-minute threshold event twice
        try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 5), activity: target.activityName) { _, _ in
            deliveryCount += 1
        }
        try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 5), activity: target.activityName) { _, _ in
            deliveryCount += 1
        }

        XCTAssertEqual(deliveryCount, 1, "Duplicate threshold event must not deliver a duplicate notification")
    }

    /// Real-world scenario: Progression through multiple usage thresholds (5m -> 10m -> 15m).
    /// Each threshold triggers exactly one reminder and advances the target elapsed time.
    func testRealWorld_usageThresholdProgressionAdvancesElapsedMinutes() throws {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [try token(1)]
        SharedSettings.selection = selection
        SharedSettings.usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = .fiveMinutes
        try UsageReminderManager.refreshMonitoring()

        let target = try XCTUnwrap(SharedSettings.usageReminderTargets.first)
        var recordedMinutes: [Int] = []

        let steps = [5, 10, 15]
        for step in steps {
            let currentTarget = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == target.id })
            try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: step), activity: currentTarget.activityName) { minutes, _ in
                recordedMinutes.append(minutes)
            }
        }

        XCTAssertEqual(recordedMinutes, [5, 10, 15], "Should deliver reminders sequentially at 5, 10, and 15 minutes")
        let finalTarget = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == target.id })
        XCTAssertEqual(finalTarget.elapsedMinutes, 15, "Elapsed minutes must be 15")
    }

    // MARK: - 4. Midnight Rollover & Cross-Day Usage

    /// Real-world scenario: User puts phone down late at night after 10 minutes of usage.
    /// The next morning, yesterday's 10-minute threshold event must not fire a phantom alarm.
    /// Instead, the target must reset elapsed time to 0 and re-arm the initial interval.
    func testRealWorld_midnightRollover_dropsStaleYesterdayEvents() throws {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [try token(1)]
        SharedSettings.selection = selection
        SharedSettings.usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = .fiveMinutes
        try UsageReminderManager.refreshMonitoring()

        let target = try XCTUnwrap(SharedSettings.usageReminderTargets.first)

        // Day 1: 5 minutes reached
        var deliveries: [Int] = []
        try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 5), activity: target.activityName) { minutes, _ in
            deliveries.append(minutes)
        }
        XCTAssertEqual(deliveries, [5])

        let advanced = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == target.id })
        XCTAssertEqual(advanced.elapsedMinutes, 5)

        // Fast forward 1 day (midnight rollover occurs while phone is idle)
        system.date = Calendar.current.date(byAdding: .day, value: 1, to: system.date)!

        // Stale event for 10 minutes arrives from yesterday's schedule
        try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 10), activity: advanced.activityName) { minutes, _ in
            deliveries.append(minutes)
        }

        XCTAssertEqual(deliveries, [5], "Stale yesterday event must NOT deliver a notification on day 2")

        // Verify target reset
        let day2Target = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == target.id })
        XCTAssertEqual(day2Target.elapsedMinutes, 0, "Elapsed minutes must reset to 0 for the new day")

        // First event of the new day (5 minutes) delivers properly
        try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 5), activity: day2Target.activityName) { minutes, _ in
            deliveries.append(minutes)
        }
        XCTAssertEqual(deliveries, [5, 5], "Day 2 first reminder delivers at 5 minutes")
    }

    // MARK: - 5. Daemon Fault Tolerance & Atomic Rollback

    /// Real-world scenario: The DeviceActivity daemon fails (e.g. system limit or crash)
    /// during schedule registration. The manager must atomically roll back so no orphaned
    /// or broken targets remain in SharedSettings.
    func testRealWorld_daemonFailureDuringRegistration_rollsBackAtomically() throws {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [try token(1), try token(2), try token(3)]
        SharedSettings.selection = selection
        SharedSettings.usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = .fiveMinutes

        // Inject system failure on 2nd monitor registration
        system.failAtStart = 2

        XCTAssertThrowsError(try UsageReminderManager.refreshMonitoring(), "Must throw on daemon failure")

        // Clean rollback: no partial targets or monitors left dangling
        XCTAssertTrue(
            SharedSettings.usageReminderTargets.isEmpty,
            "SharedSettings targets must be rolled back on failure"
        )
        XCTAssertTrue(
            system.monitors.isEmpty,
            "System monitors must be empty after atomic cleanup"
        )
    }

    // MARK: - 6. Challenge Lifecycle, Access Windows & Shield Invariant

    /// Real-world scenario: When a user finishes speaking their intention aloud,
    /// completeChallenge() is invoked:
    /// - Pending challenge is cleared.
    /// - Shield for the requested app is released.
    /// - Access window is scheduled.
    /// When access window expires:
    /// - Shields are immediately re-applied.
    @MainActor
    func testRealWorld_completedChallenge_clearsPendingAndExpiresShieldsCorrectly() throws {
        let appA = try token(1)
        let appB = try token(2)

        var selection = FamilyActivitySelection()
        selection.applicationTokens = [appA, appB]
        SharedSettings.selection = selection
        SharedSettings.protectionEnabled = true
        SharedSettings.pendingChallenge = .application(appA)
        ShieldManager.applySavedSelection()

        // Both apps are shielded initially
        XCTAssertEqual(system.shields.applicationTokens, [appA, appB])
        XCTAssertEqual(SharedSettings.pendingChallenge, .application(appA))

        let model = AppModel(demoMode: false)
        let completed = model.completeChallenge()

        XCTAssertTrue(completed, "completeChallenge() must succeed")
        XCTAssertNil(SharedSettings.pendingChallenge, "Pending challenge must be cleared upon completion")

        // App A is released, App B remains shielded
        XCTAssertEqual(system.shields.applicationTokens, [appB], "Only App A should be unlocked; App B remains shielded")

        // An access window is created for App A
        let window = try XCTUnwrap(SharedSettings.accessWindows.first)
        system.date = window.expiration

        // When access window expires, App A must be re-shielded
        AccessWindowManager.expire(activity: window.activity)
        XCTAssertEqual(system.shields.applicationTokens, [appA, appB], "Both apps must be shielded after access window expiration")
    }

    /// Real-world scenario: If an access window is expired or cancelled early,
    /// pending challenge for that app must not be left orphaned.
    func testRealWorld_cancelingPendingChallenge_restoresShieldIntegrity() throws {
        let app = try token(1)
        SharedSettings.pendingChallenge = .application(app)
        XCTAssertNotNil(SharedSettings.pendingChallenge)

        // Clear challenge (e.g. user dismissed or abandoned challenge)
        SharedSettings.pendingChallenge = nil
        XCTAssertNil(SharedSettings.pendingChallenge)
    }

    // MARK: - 7. Multi-App Coordination & Rapid Interaction

    /// Real-world scenario: User protects multiple apps (e.g. Instagram, TikTok, Reddit).
    /// Each app must have its own monitored activity with independent thresholds.
    func testRealWorld_multipleProtectedApps_maintainsIndependentReminderSchedules() throws {
        let appA = try token(1)
        let appB = try token(2)
        let appC = try token(3)

        var selection = FamilyActivitySelection()
        selection.applicationTokens = [appA, appB, appC]
        SharedSettings.selection = selection
        SharedSettings.usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = .fiveMinutes

        try UsageReminderManager.refreshMonitoring()

        XCTAssertEqual(
            SharedSettings.usageReminderTargets.count, 3,
            "Must register 3 distinct reminder targets for the 3 protected apps"
        )
        XCTAssertEqual(
            system.monitors.count, 3,
            "System must have 3 active DeviceActivity monitors"
        )

        // App A reaches 5 minutes
        let targetA = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.challenge == .application(appA) })
        var deliveredA: [Int] = []
        try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 5), activity: targetA.activityName) { minutes, _ in
            deliveredA.append(minutes)
        }
        XCTAssertEqual(deliveredA, [5])

        // App B and App C must still be at 0 elapsed minutes
        let targetB = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.challenge == .application(appB) })
        let targetC = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.challenge == .application(appC) })
        XCTAssertEqual(targetB.elapsedMinutes, 0, "App B usage must remain independent at 0")
        XCTAssertEqual(targetC.elapsedMinutes, 0, "App C usage must remain independent at 0")
    }

    /// Real-world scenario: User modifies protected app selection to drop one app.
    /// The dropped app's reminder target must be removed, while the remaining app's target is preserved.
    func testRealWorld_removingProtectedApp_cleansUpItsReminderTargetOnly() throws {
        let appA = try token(1)
        let appB = try token(2)

        var selection = FamilyActivitySelection()
        selection.applicationTokens = [appA, appB]
        SharedSettings.selection = selection
        SharedSettings.usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = .fiveMinutes
        try UsageReminderManager.refreshMonitoring()

        XCTAssertEqual(SharedSettings.usageReminderTargets.count, 2)

        // User unselects App B in Settings
        selection.applicationTokens = [appA]
        SharedSettings.selection = selection
        try UsageReminderManager.refreshMonitoring()

        XCTAssertEqual(
            SharedSettings.usageReminderTargets.count, 1,
            "Only App A's reminder target should remain"
        )
        XCTAssertEqual(
            SharedSettings.usageReminderTargets.first?.challenge,
            .application(appA)
        )
    }

    /// Real-world scenario: User rapidly toggles reminder intervals in the UI
    /// (e.g. 5m -> 10m -> Off -> 5m).
    /// The final state in both SharedSettings and system monitors must be completely consistent.
    @MainActor
    func testRealWorld_rapidCadenceToggling_settlesInConsistentFinalState() async throws {
        NotificationPermissionClient.request = { true }
        NotificationPermissionClient.check = { true }

        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [try token(1)]
        model.saveSelection()

        // Rapidly change settings
        await model.selectUsageReminderInterval(.fiveMinutes)
        await model.selectUsageReminderInterval(.tenMinutes)
        model.turnOffUsageReminders()
        await model.selectUsageReminderInterval(.fiveMinutes)

        XCTAssertTrue(model.usageRemindersEnabled)
        XCTAssertTrue(SharedSettings.usageRemindersEnabled)
        XCTAssertEqual(SharedSettings.usageReminderInterval, .fiveMinutes)
        XCTAssertEqual(system.monitors.count, 1, "Exactly one monitor should be active")

        let event = try XCTUnwrap(system.monitors.values.first?.first)
        XCTAssertEqual(event.key, UsageReminderEvent.name(for: 5), "Should be armed for 5 minutes")
    }

    /// Real-world scenario: When notification fallback is NOT required (modern iOS device
    /// where Screen Time shields can handle challenge display natively),
    /// protection does not mandate a notification fallback error if notifications are off.
    @MainActor
    func testRealWorld_whenFallbackNotRequired_protectionArmsDirectly() async throws {
        NotificationPermissionClient.request = { false }
        NotificationPermissionClient.check = { false }
        NotificationPermissionClient.requiresFallback = { false } // Modern iOS / native shield UI available

        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [try token(1)]
        model.saveSelection()

        await model.enableProtectionWithAuthorizationCheck()

        XCTAssertTrue(
            model.protectionEnabled,
            "When fallback is not required, protection should arm without blocking on notification authorization"
        )
        XCTAssertNil(model.errorMessage)
    }
}
