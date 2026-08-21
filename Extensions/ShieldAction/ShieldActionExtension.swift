import ManagedSettings
import OSLog
import UserNotifications

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, challenge: .application(application), completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, challenge: .category(category), completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, challenge: .webDomain(webDomain), completionHandler: completionHandler)
    }

    private func respond(
        to action: ShieldAction,
        challenge: PendingChallenge,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            OutLoudLog.challenge.info(
                "Shield pause started; challenge kind: \(challenge.logName, privacy: .public)"
            )
            SharedSettings.pendingChallenge = challenge
#if compiler(>=6.3)
            if #available(iOS 26.5, *) {
                OutLoudLog.challenge.debug("Opening parental controls app directly")
                completionHandler(.openParentalControlsApp)
            } else {
                notifyAndClose(completionHandler: completionHandler)
            }
#else
            notifyAndClose(completionHandler: completionHandler)
#endif
        case .secondaryButtonPressed,
             .firstSecondarySubmenuItemPressed,
             .secondSecondarySubmenuItemPressed,
             .thirdSecondarySubmenuItemPressed:
            OutLoudLog.challenge.info("Shield pause declined")
            completionHandler(.close)
        @unknown default:
            OutLoudLog.challenge.notice("Received unknown shield action")
            completionHandler(.close)
        }
    }

    private func notifyAndClose(
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        OutLoudLog.challenge.debug("Using notification fallback to open challenge")
        sendChallengeNotification()
        completionHandler(.close)
    }

    private func sendChallengeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Say it out loud"
        content.body = "Tap to say “\(SharedSettings.phrase)” and continue."
        content.sound = .default
        content.categoryIdentifier = "OUTLOUD_CHALLENGE"

        let request = UNNotificationRequest(
            identifier: "outloud.pending-challenge",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                OutLoudLog.challenge.error(
                    "Failed to schedule challenge notification: \(error.localizedDescription, privacy: .public)"
                )
            } else {
                OutLoudLog.challenge.debug("Challenge notification scheduled")
            }
        }
    }
}
