import UserNotifications
import XCTest
@testable import OutLoud

final class ProtectionReminderTests: ScreenTimeFlowTestCase {

    func testProtectionReminderEscalatingOffsets() {
        let offsets = ProtectionReminderNotification.standardOffsets
        XCTAssertEqual(offsets.first, 3600, "First reminder must be at 1 hour (3600 seconds)")
        XCTAssertEqual(offsets[1], 10800, "Second reminder must be at 3 hours (10800 seconds)")
        XCTAssertEqual(offsets[2], 21600, "Third reminder must be at 6 hours (21600 seconds)")
        XCTAssertEqual(offsets[3], 43200, "Fourth reminder must be at 12 hours (43200 seconds)")
        XCTAssertEqual(offsets[4], 64800, "Fifth reminder must be at 18 hours (64800 seconds)")
        XCTAssertEqual(offsets[5], 86400, "Sixth reminder must be at 24 hours (86400 seconds)")
        XCTAssertTrue(offsets.count >= 6, "Must schedule escalating reminders across multiple days")
    }

    func testProtectionReminderIdentifiersAndMatching() {
        let id1h = ProtectionReminderNotification.identifier(for: 3600)
        XCTAssertEqual(id1h, "outloud.protection-reminder.3600")
        XCTAssertTrue(ProtectionReminderNotification.isProtectionReminder(id1h))
        XCTAssertTrue(ProtectionReminderNotification.isProtectionReminder("outloud.protection-reminder.10800"))
        XCTAssertFalse(ProtectionReminderNotification.isProtectionReminder("outloud.usage-reminder"))
        XCTAssertFalse(ProtectionReminderNotification.isProtectionReminder("outloud.pending-challenge"))
    }

    func testProtectionReminderCopyMeetsToughLoveContract() {
        let title1h = ProtectionReminderNotification.title(for: 3600)
        let body1h = ProtectionReminderNotification.body(for: 3600)
        XCTAssertEqual(title1h, "Protection is off")
        XCTAssertEqual(body1h, "Protection is off. Turn it back on and stop doomscrolling like a loser.")

        let title3h = ProtectionReminderNotification.title(for: 10800)
        let body3h = ProtectionReminderNotification.body(for: 10800)
        XCTAssertEqual(title3h, "Still scrolling unprotected?")
        XCTAssertEqual(body3h, "It’s been 3 hours without protection. Turn it back on and stop doomscrolling like a loser.")

        let title6h = ProtectionReminderNotification.title(for: 21600)
        let body6h = ProtectionReminderNotification.body(for: 21600)
        XCTAssertEqual(title6h, "Protection is still off")
        XCTAssertEqual(body6h, "It’s been 6 hours without protection. Turn it back on and stop doomscrolling like a loser.")

        let body24h = ProtectionReminderNotification.body(for: 86400)
        XCTAssertEqual(body24h, "A full day without protection. Turn it back on and stop doomscrolling like a loser.")
    }

    func testProtectionReminderRequestsAreTimeSensitive() {
        let now = Date()
        let requests = ProtectionReminderManager.makeRequests(from: now, now: now)

        XCTAssertFalse(requests.isEmpty, "Should generate protection reminder requests")
        for request in requests {
            XCTAssertEqual(
                request.content.interruptionLevel,
                .timeSensitive,
                "Protection reminders must be time-sensitive to break through Focus/DND"
            )
            XCTAssertEqual(request.content.sound, .default, "Must play an audible alert sound")
            XCTAssertEqual(request.content.relevanceScore, 1.0, "Must have maximum relevance score")
            XCTAssertEqual(
                request.content.categoryIdentifier,
                ProtectionReminderNotification.categoryIdentifier,
                "Must specify the protection reminder category"
            )
            XCTAssertTrue(
                ProtectionReminderNotification.isProtectionReminder(request.identifier),
                "Request identifier must match reminder prefix"
            )
            guard let trigger = request.trigger as? UNTimeIntervalNotificationTrigger else {
                XCTFail("Trigger must be a UNTimeIntervalNotificationTrigger")
                continue
            }
            XCTAssertFalse(trigger.repeats, "Each escalating reminder milestone trigger is one-shot")
            XCTAssertGreaterThan(trigger.timeInterval, 0, "Delay must be positive")
        }
    }

    @MainActor
    func testTurningProtectionOffSchedulesReminders() async throws {
        var scheduled: [UNNotificationRequest] = []
        var removedPending: [[String]] = []
        var removedDelivered: [[String]] = []
        ProtectionReminderManager.addRequest = { scheduled.append($0) }
        ProtectionReminderManager.removePendingRequests = { removedPending.append($0) }
        ProtectionReminderManager.removeDeliveredNotifications = { removedDelivered.append($0) }

        NotificationPermissionClient.request = { true }
        NotificationPermissionClient.check = { true }
        NotificationPermissionClient.requiresFallback = { false }

        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [try token(1)]
        model.saveSelection()
        await model.finishOnboarding(enableProtection: true)

        XCTAssertTrue(model.protectionEnabled)
        scheduled.removeAll()
        removedPending.removeAll()
        removedDelivered.removeAll()

        // Turn protection OFF
        model.setProtection(false)

        XCTAssertFalse(model.protectionEnabled)
        XCTAssertNotNil(SharedSettings.protectionDisabledDate, "Disabled date must be recorded")
        XCTAssertFalse(scheduled.isEmpty, "Reminders must be scheduled when protection is turned off")

        let firstDelay = try XCTUnwrap(
            (scheduled.first?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
        )
        XCTAssertEqual(firstDelay, 3600, accuracy: 5.0, "First reminder delay should be ~1 hour")
    }

    @MainActor
    func testTurningProtectionOnCancelsReminders() async throws {
        var scheduled: [UNNotificationRequest] = []
        var removedPending: [[String]] = []
        var removedDelivered: [[String]] = []
        ProtectionReminderManager.addRequest = { scheduled.append($0) }
        ProtectionReminderManager.removePendingRequests = { removedPending.append($0) }
        ProtectionReminderManager.removeDeliveredNotifications = { removedDelivered.append($0) }

        NotificationPermissionClient.request = { true }
        NotificationPermissionClient.check = { true }
        NotificationPermissionClient.requiresFallback = { false }

        let model = AppModel(demoMode: false)
        model.selection.applicationTokens = [try token(1)]
        model.saveSelection()
        await model.finishOnboarding(enableProtection: false)

        XCTAssertFalse(model.protectionEnabled)
        XCTAssertNotNil(SharedSettings.protectionDisabledDate)
        XCTAssertFalse(scheduled.isEmpty)

        scheduled.removeAll()
        removedPending.removeAll()
        removedDelivered.removeAll()

        // Turn protection ON
        model.setProtection(true)

        XCTAssertTrue(model.protectionEnabled)
        XCTAssertNil(SharedSettings.protectionDisabledDate, "Disabled date must be cleared when protection is on")
        XCTAssertFalse(removedPending.isEmpty, "Pending reminder requests must be cancelled")
        XCTAssertFalse(removedDelivered.isEmpty, "Delivered reminders must be cleared")
    }

    @MainActor
    func testRefreshPendingChallengeMaintainsRemindersWhenProtectionOff() async throws {
        var scheduled: [UNNotificationRequest] = []
        ProtectionReminderManager.addRequest = { scheduled.append($0) }
        ProtectionReminderManager.removePendingRequests = { _ in }
        ProtectionReminderManager.removeDeliveredNotifications = { _ in }

        let model = AppModel(demoMode: false)
        model.onboardingCompleted = true
        SharedSettings.onboardingCompleted = true
        model.protectionEnabled = false
        SharedSettings.protectionEnabled = false
        SharedSettings.protectionDisabledDate = ScreenTimeClient.current.now().addingTimeInterval(-7200) // 2 hours ago

        model.refreshPendingChallenge()

        XCTAssertFalse(scheduled.isEmpty, "Should schedule upcoming milestones when app refreshes")
        // Since 2 hours have passed, 1-hour milestone (3600s) has passed.
        // The first upcoming milestone is 3 hours (10800s - 7200s = 3600s remaining).
        let firstDelay = try XCTUnwrap(
            (scheduled.first?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
        )
        XCTAssertEqual(firstDelay, 3600, accuracy: 5.0, "Upcoming milestone should fire in 1 hour")
    }
}
