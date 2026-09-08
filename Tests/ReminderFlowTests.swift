import DeviceActivity
import FamilyControls
import XCTest
@testable import OutLoud

final class ReminderFlowTests: ScreenTimeFlowTestCase {
    @MainActor
    func testNotificationDenialDoesNotEnableRemindersAndPermissionRecoveryStartsThem() async throws {
        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [try token(1)]
        model.saveSelection()
        await model.selectUsageReminderInterval(.fiveMinutes)
        XCTAssertFalse(model.usageRemindersEnabled)
        XCTAssertFalse(SharedSettings.usageRemindersEnabled)
        XCTAssertTrue(system.monitors.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        NotificationPermissionClient.request = { true }
        await model.selectUsageReminderInterval(.fiveMinutes)
        XCTAssertTrue(model.usageRemindersEnabled)
        XCTAssertEqual(system.monitors.count, 1)
        XCTAssertNil(model.errorMessage)
    }

    func configure() throws {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [try token(1), try token(2)]
        SharedSettings.selection = selection
        SharedSettings.usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = .fiveMinutes
        try UsageReminderManager.refreshMonitoring()
    }

    func testExtensionCallbackAdvancesAcrossCadenceChangeAndRejectsDuplicate() throws {
        try configure()
        let first = try XCTUnwrap(SharedSettings.usageReminderTargets.first)
        var delivered: [Int] = []
        func fire(_ minutes: Int, _ activity: DeviceActivityName) throws {
            try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: minutes), activity: activity) { minutes, _ in
                delivered.append(minutes)
            }
        }
        try fire(5, first.activityName)
        try fire(5, first.activityName)
        XCTAssertEqual(delivered, [5])
        SharedSettings.usageReminderInterval = .tenMinutes
        try UsageReminderManager.refreshMonitoring()
        let changed = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == first.id })
        let event = try XCTUnwrap(system.monitors[changed.activityName]?.first)
        XCTAssertEqual(event.key, UsageReminderEvent.name(for: 10))
        XCTAssertEqual(event.value.threshold.minute, 10)
        try fire(10, changed.activityName)
        let advanced = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == first.id })
        XCTAssertEqual(system.monitors[advanced.activityName]?.keys.first, UsageReminderEvent.name(for: 20))
        try fire(20, advanced.activityName)
        XCTAssertEqual(delivered, [5, 10, 20])
        XCTAssertEqual(SharedSettings.usageReminderTargets.first { $0.id != first.id }?.elapsedMinutes, 0)
        SharedSettings.usageRemindersEnabled = false
        UsageReminderManager.stopMonitoring()
        let latest = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == first.id })
        try fire(30, latest.activityName)
        XCTAssertEqual(delivered, [5, 10, 20])
        XCTAssertTrue(system.monitors.isEmpty)
    }

    func testMidnightResetIsIdempotentAndOldEventsAreIgnored() throws {
        try configure()
        let first = try XCTUnwrap(SharedSettings.usageReminderTargets.first)
        try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 5), activity: first.activityName) { _, _ in }
        let advanced = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == first.id })
        system.date = Calendar.current.date(byAdding: .day, value: 1, to: system.date)!
        try UsageReminderManager.resetForNewDayIfNeeded(activity: advanced.activityName)
        let reset = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == first.id })
        XCTAssertEqual(reset.elapsedMinutes, 0)
        XCTAssertEqual(system.monitors[reset.activityName]?.keys.first, UsageReminderEvent.name(for: 5))
        let starts = system.starts
        try UsageReminderManager.resetForNewDayIfNeeded(activity: reset.activityName)
        XCTAssertEqual(system.starts, starts)
        try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 10), activity: advanced.activityName) { _, _ in
            XCTFail("Yesterday's event must not deliver a reminder")
        }
    }

    func testFailedNextMonitorCanBeRestoredWithoutRepeatingNotification() throws {
        try configure()
        let target = try XCTUnwrap(SharedSettings.usageReminderTargets.first)
        system.failuresRemaining = 1
        var deliveries = 0
        XCTAssertThrowsError(try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 5), activity: target.activityName) { _, _ in deliveries += 1 })
        let advanced = try XCTUnwrap(SharedSettings.usageReminderTargets.first { $0.id == target.id })
        XCTAssertEqual(advanced.elapsedMinutes, 5)
        XCTAssertNil(system.monitors[advanced.activityName])
        try UsageReminderManager.ensureMonitoring()
        XCTAssertNotNil(system.monitors[advanced.activityName])
        try UsageReminderManager.handleThreshold(UsageReminderEvent.name(for: 5), activity: target.activityName) { _, _ in deliveries += 1 }
        XCTAssertEqual(deliveries, 1)
    }

    func testFailedRefreshCleansUpPartiallyStartedMonitors() throws {
        try configure()
        system.failAtStart = system.starts + 2
        XCTAssertThrowsError(try UsageReminderManager.refreshMonitoring())
        XCTAssertTrue(system.monitors.isEmpty)
        XCTAssertTrue(SharedSettings.usageReminderTargets.isEmpty)
    }
}
