import SwiftUI
import OSLog
import UserNotifications

@main
struct OutLoudApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
#if DEBUG && targetEnvironment(simulator)
        _model = StateObject(wrappedValue: UITestScenario.makeModel() ?? AppModel())
#else
        _model = StateObject(wrappedValue: AppModel())
#endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let message = model.challengeRecoveryMessage {
                VStack(spacing: 24) {
                    Text("App selection needed").font(.title.bold())
                    Text(message).multilineTextAlignment(.center)
                    Button("Back to OutLoud") { model.cancelChallenge() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
            } else if model.pendingChallenge != nil {
                ChallengeView()
                    .id(model.challengeSessionID)
            } else if !model.onboardingCompleted {
                OnboardingView()
            } else {
                HomeView()
            }
        }
        .onAppear {
            OutLoudLog.lifecycle.info("Root view appeared")
            model.refreshPendingChallenge()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                OutLoudLog.lifecycle.debug("Scene became active")
                model.refreshPendingChallenge()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .outLoudChallengeRequested)) { _ in
            OutLoudLog.challenge.debug("Challenge notification received by root view")
            model.refreshPendingChallenge()
        }
        .onReceive(NotificationCenter.default.publisher(for: .outLoudProtectionReenabled)) { notification in
            model.refreshAfterProtectionAction(error: notification.userInfo?["error"] as? String)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerNotificationCategories(center: center)
        OutLoudLog.lifecycle.info("Application finished launching")
        return true
    }

    private func registerNotificationCategories(center: UNUserNotificationCenter) {
        let lockAction = UNNotificationAction(
            identifier: UsageReminderNotification.lockActionIdentifier,
            title: "Lock Selected Apps Now",
            options: [.destructive, .foreground]
        )
        let usageCategory = UNNotificationCategory(
            identifier: UsageReminderNotification.categoryIdentifier,
            actions: [lockAction],
            intentIdentifiers: [],
            options: []
        )
        let enableProtectionAction = UNNotificationAction(
            identifier: ProtectionReminderNotification.reenableActionIdentifier,
            title: "Turn Protection On",
            options: [.foreground]
        )
        let protectionCategory = UNNotificationCategory(
            identifier: ProtectionReminderNotification.categoryIdentifier,
            actions: [enableProtectionAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([usageCategory, protectionCategory])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            defer { completionHandler() }
            await Self.performNotificationAction(identifier: identifier, actionIdentifier: response.actionIdentifier)
        }
    }

    @MainActor
    static func performNotificationAction(identifier: String, actionIdentifier: String) async {
        let lockRequested = identifier == UsageReminderNotification.identifier
            && actionIdentifier == UsageReminderNotification.lockActionIdentifier
        let enableRequested = ProtectionReminderNotification.isProtectionReminder(identifier)
            && actionIdentifier == ProtectionReminderNotification.reenableActionIdentifier
        if lockRequested || enableRequested {
            // This explicit action locks every selected item, in either timing
            // mode, including when protection was off. Recheck both permissions.
            let model = AppModel(demoMode: false)
            model.cancelChallenge()
            await model.enableProtectionWithAuthorizationCheck()
            NotificationCenter.default.post(name: .outLoudProtectionReenabled, object: nil,
                                            userInfo: model.errorMessage.map { ["error": $0] })
            if model.errorMessage == nil { SensoryFeedbackClient.shared.lockToggle(isOn: true) }
        } else if identifier == "outloud.pending-challenge",
                  actionIdentifier == UNNotificationDefaultActionIdentifier {
            NotificationCenter.default.post(name: .outLoudChallengeRequested, object: nil)
        }
        // Opening a reminder's body navigates to OutLoud without changing locks.
    }
}

extension Notification.Name {
    static let outLoudChallengeRequested = Notification.Name("outloud.challenge-requested")
    static let outLoudProtectionReenabled = Notification.Name("outloud.protection-reenabled")
}
