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
            if model.pendingChallenge != nil {
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
            title: "Lock App Now",
            options: [.destructive]
        )
        let usageCategory = UNNotificationCategory(
            identifier: UsageReminderNotification.categoryIdentifier,
            actions: [lockAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([usageCategory])
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
        defer { completionHandler() }
        let identifier = response.notification.request.identifier

        if identifier == UsageReminderNotification.identifier {
            OutLoudLog.screenTime.info(
                "User engaged usage reminder; action: \(response.actionIdentifier, privacy: .public)"
            )
            ShieldManager.rearmProtection()
            AccessWindowManager.expire()
            DispatchQueue.main.async {
                SensoryFeedbackClient.shared.lockToggle(isOn: true)
            }
            return
        }

        guard identifier == "outloud.pending-challenge" else { return }

        OutLoudLog.challenge.info("User opened challenge notification")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .outLoudChallengeRequested, object: nil)
        }
    }
}

extension Notification.Name {
    static let outLoudChallengeRequested = Notification.Name("outloud.challenge-requested")
}
