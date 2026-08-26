import DeviceActivity
import OSLog
import UserNotifications

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard UsageReminderActivity.isUsageReminder(activity) else { return }

        do {
            try UsageReminderManager.resetForNewDayIfNeeded(activity: activity)
        } catch {
            OutLoudLog.screenTime.error(
                "Failed to reset daily usage reminder: \(error.localizedDescription)"
            )
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if UsageReminderActivity.isUsageReminder(activity) {
            OutLoudLog.screenTime.debug("Daily usage reminder interval ended")
            return
        }
        guard activity == SharedSettings.relockActivity else {
            OutLoudLog.screenTime.debug("Ignoring unrelated Device Activity interval")
            return
        }
        OutLoudLog.screenTime.info("Access window ended; reapplying shields")
        SharedSettings.unlockExpiration = nil
        ShieldManager.applySavedSelection()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        guard UsageReminderActivity.isUsageReminder(activity),
              SharedSettings.usageRemindersEnabled,
              let elapsedMinutes = UsageReminderEvent.elapsedMinutes(from: event),
              let target = UsageReminderManager.target(for: activity),
              elapsedMinutes == target.elapsedMinutes
                + SharedSettings.usageReminderInterval.rawValue else {
            OutLoudLog.screenTime.debug("Ignoring unrelated Device Activity threshold")
            return
        }

        OutLoudLog.screenTime.info(
            "Usage reminder reached; elapsed minutes: \(elapsedMinutes, privacy: .public)"
        )
        sendUsageReminder(elapsedMinutes: elapsedMinutes, appName: target.appName)

        do {
            try UsageReminderManager.advance(
                activity: activity,
                elapsedMinutes: elapsedMinutes
            )
        } catch {
            OutLoudLog.screenTime.error(
                "Failed to schedule the next usage reminder: \(error.localizedDescription)"
            )
        }
    }

    private func sendUsageReminder(elapsedMinutes: Int, appName: String) {
        let content = UNMutableNotificationContent()
        content.title = UsageReminderNotification.title(
            elapsedMinutes: elapsedMinutes,
            appName: appName
        )
        content.body = UsageReminderNotification.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.threadIdentifier = "outloud.usage-reminders"
        content.categoryIdentifier = "OUTLOUD_USAGE_REMINDER"

        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(
            withIdentifiers: [UsageReminderNotification.identifier]
        )
        let request = UNNotificationRequest(
            identifier: UsageReminderNotification.identifier,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                OutLoudLog.screenTime.error(
                    "Failed to send usage reminder: \(error.localizedDescription)"
                )
            } else {
                OutLoudLog.screenTime.debug("Usage reminder notification sent")
            }
        }
    }
}
