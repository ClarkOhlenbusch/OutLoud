import Foundation
import OSLog
import UserNotifications

enum ProtectionReminderManager {
    static var addRequest: @Sendable (UNNotificationRequest) -> Void = { request in
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                OutLoudLog.screenTime.error(
                    "Failed to schedule protection reminder (\(request.identifier, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                )
            } else {
                OutLoudLog.screenTime.debug(
                    "Scheduled protection reminder: \(request.identifier, privacy: .public)"
                )
            }
        }
    }

    static var removePendingRequests: @Sendable ([String]) -> Void = { identifiers in
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.getPendingNotificationRequests { requests in
            let reminderIDs = requests
                .map(\.identifier)
                .filter(ProtectionReminderNotification.isProtectionReminder)
            if !reminderIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: reminderIDs)
            }
        }
    }

    static var removeDeliveredNotifications: @Sendable ([String]) -> Void = { identifiers in
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.getDeliveredNotifications { notifications in
            let reminderIDs = notifications
                .map { $0.request.identifier }
                .filter(ProtectionReminderNotification.isProtectionReminder)
            if !reminderIDs.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: reminderIDs)
            }
        }
    }

    static func resetToLive() {
        addRequest = { request in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    OutLoudLog.screenTime.error(
                        "Failed to schedule protection reminder (\(request.identifier, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    OutLoudLog.screenTime.debug(
                        "Scheduled protection reminder: \(request.identifier, privacy: .public)"
                    )
                }
            }
        }
        removePendingRequests = { identifiers in
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.getPendingNotificationRequests { requests in
                let reminderIDs = requests
                    .map(\.identifier)
                    .filter(ProtectionReminderNotification.isProtectionReminder)
                if !reminderIDs.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: reminderIDs)
                }
            }
        }
        removeDeliveredNotifications = { identifiers in
            let center = UNUserNotificationCenter.current()
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
            center.getDeliveredNotifications { notifications in
                let reminderIDs = notifications
                    .map { $0.request.identifier }
                    .filter(ProtectionReminderNotification.isProtectionReminder)
                if !reminderIDs.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: reminderIDs)
                }
            }
        }
    }

    static func makeRequests(
        from referenceDate: Date,
        now: Date = ScreenTimeClient.current.now()
    ) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        let elapsed = max(0, now.timeIntervalSince(referenceDate))

        var milestones = ProtectionReminderNotification.standardOffsets
        let maxWindow = max(elapsed + 72 * 3600, 72 * 3600)
        var nextOffset: TimeInterval = 78 * 3600
        while nextOffset <= maxWindow && milestones.count < 30 {
            milestones.append(nextOffset)
            nextOffset += 6 * 3600
        }

        for offset in milestones {
            let delay = offset - elapsed
            guard delay > 1 else { continue }

            let content = UNMutableNotificationContent()
            content.title = ProtectionReminderNotification.title(for: offset)
            content.body = ProtectionReminderNotification.body(for: offset)
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
            content.categoryIdentifier = ProtectionReminderNotification.categoryIdentifier

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(
                identifier: ProtectionReminderNotification.identifier(for: offset),
                content: content,
                trigger: trigger
            )
            requests.append(request)
        }

        return requests
    }

    static func scheduleReminders(
        from referenceDate: Date? = nil,
        now: Date = ScreenTimeClient.current.now()
    ) {
        let baseDate = referenceDate ?? SharedSettings.protectionDisabledDate ?? now
        let requests = makeRequests(from: baseDate, now: now)
        OutLoudLog.screenTime.info(
            "Scheduling \(requests.count, privacy: .public) protection reminder(s)"
        )
        for request in requests {
            addRequest(request)
        }
    }

    static func ensureRemindersScheduled(
        from referenceDate: Date? = nil,
        now: Date = ScreenTimeClient.current.now()
    ) {
        guard !SharedSettings.protectionEnabled else {
            cancelReminders()
            return
        }
        scheduleReminders(from: referenceDate, now: now)
    }

    static func cancelReminders() {
        OutLoudLog.screenTime.info("Cancelling all protection reminder notifications")
        let identifiers = ProtectionReminderNotification.allIdentifiers
        removePendingRequests(identifiers)
        removeDeliveredNotifications(identifiers)
    }
}
