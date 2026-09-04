import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: FamilyActivitySelection
    @Published var phrase: String
    @Published var acceptsSimilarAcknowledgements: Bool
    @Published var protectionEnabled: Bool
    @Published var askAgainMode: AskAgainMode
    @Published var gracePeriod: TimeInterval
    @Published var pendingChallenge: PendingChallenge?
    @Published var challengeSessionID: UUID
    @Published var authorizationStatus: AuthorizationStatus
    @Published var onboardingCompleted: Bool
    @Published var onboardingStep: OnboardingStep
    @Published var returnMappings: [ApplicationReturnMapping]
    @Published var usageRemindersEnabled: Bool
    @Published var usageReminderInterval: UsageReminderInterval
    @Published private(set) var isRequestingScreenTimeAuthorization = false
    @Published var errorMessage: String?
    @Published var demoSelectedApps: Set<String> = ["Instagram", "TikTok"]

    init() {
        selection = SharedSettings.selection
        phrase = SharedSettings.phrases.joined(separator: "\n")
        acceptsSimilarAcknowledgements = SharedSettings.acceptsSimilarAcknowledgements
        protectionEnabled = SharedSettings.protectionEnabled
        askAgainMode = SharedSettings.askAgainMode
        gracePeriod = SharedSettings.gracePeriod
        pendingChallenge = SharedSettings.pendingChallenge
            ?? (SharedSettings.challengeRequested ? .selection : nil)
        challengeSessionID = SharedSettings.challengeRequestID ?? UUID()
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        onboardingCompleted = SharedSettings.onboardingCompleted
        onboardingStep = OnboardingStep(storedValue: SharedSettings.onboardingStep)
        returnMappings = SharedSettings.returnMappings
        usageRemindersEnabled = SharedSettings.usageRemindersEnabled
        usageReminderInterval = SharedSettings.usageReminderInterval

        OutLoudLog.lifecycle.info(
            "Model initialized; onboarding complete: \(self.onboardingCompleted, privacy: .public), protection enabled: \(self.protectionEnabled, privacy: .public), selected count: \(self.selectedItemCount, privacy: .public)"
        )
        if acceptsSimilarAcknowledgements {
#if !targetEnvironment(simulator)
            Task { await FlexibleAcknowledgementMatcher.prepareModelAssets() }
#endif
        }
        if usageRemindersEnabled && !isDemoMode {
            do {
                try UsageReminderManager.ensureMonitoring()
            } catch {
                OutLoudLog.screenTime.error(
                    "Failed to restore usage reminder monitoring: \(error.localizedDescription)"
                )
            }
        }
    }

    var isDemoMode: Bool {
#if targetEnvironment(simulator)
        true
#else
        ProcessInfo.processInfo.arguments.contains("--demo")
#endif
    }

    var isAuthorized: Bool {
        isDemoMode || authorizationStatus.grantsOutLoudScreenTimeAccess
    }

    var phrases: [String] {
        PhraseMatcher.phrases(from: phrase)
    }

    var phraseSummary: String {
        if acceptsSimilarAcknowledgements { return "Own words" }
        let savedPhrases = phrases
        return savedPhrases.count == 1 ? "1 phrase" : "\(savedPhrases.count) phrases"
    }

    var selectedItemCount: Int {
        isDemoMode ? demoSelectedApps.count : selection.selectedItemCount
    }

    var protectedApplicationTokens: [ApplicationToken] {
        Array(selection.applicationTokens)
    }

    var mappedApplicationCount: Int {
        selection.applicationTokens.filter { returnDestination(for: $0) != nil }.count
    }

    var needsReturnSetup: Bool {
        !isDemoMode && mappedApplicationCount < selection.applicationTokens.count
    }

    var hasUnsupportedReturnSelection: Bool {
        !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    func requestAuthorization() async {
        guard !isRequestingScreenTimeAuthorization else { return }
        isRequestingScreenTimeAuthorization = true
        errorMessage = nil
        defer { isRequestingScreenTimeAuthorization = false }

        OutLoudLog.onboarding.info("Requesting Screen Time authorization")
        for attempt in 0...1 {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                authorizationStatus = AuthorizationCenter.shared.authorizationStatus

                guard isAuthorized else {
                    OutLoudLog.onboarding.error(
                        "Screen Time authorization returned without an approved status; status: \(self.authorizationStatus.description, privacy: .public)"
                    )
                    errorMessage = "Screen Time access didn’t finish setting up. Tap Allow access to try again."
                    return
                }

                let notificationsAllowed = await requestFallbackNotificationAuthorization()
                OutLoudLog.onboarding.info(
                    "Screen Time authorization finished; approved: true, notifications allowed: \(notificationsAllowed, privacy: .public)"
                )
                return
            } catch let familyControlsError as FamilyControlsError {
                authorizationStatus = AuthorizationCenter.shared.authorizationStatus
                if attempt == 0, familyControlsError.isTransientAuthorizationFailure {
                    OutLoudLog.onboarding.notice(
                        "Retrying transient Screen Time authorization failure: \(familyControlsError.localizedDescription, privacy: .public)"
                    )
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    continue
                }
                OutLoudLog.onboarding.error(
                    "Screen Time authorization failed: \(familyControlsError.localizedDescription, privacy: .public)"
                )
                errorMessage = familyControlsError.outLoudAuthorizationMessage
                return
            } catch {
                authorizationStatus = AuthorizationCenter.shared.authorizationStatus
                OutLoudLog.onboarding.error(
                    "Screen Time authorization failed: \(error.localizedDescription, privacy: .public)"
                )
                errorMessage = "Screen Time access couldn’t be set up. Tap Allow access to try again."
                return
            }
        }
    }

    func saveSelection() {
        guard !isDemoMode else {
            OutLoudLog.screenTime.debug(
                "Updated simulator selection; selected count: \(self.selectedItemCount, privacy: .public)"
            )
            return
        }
        pruneReturnMappings()
        SharedSettings.selection = selection
        OutLoudLog.screenTime.info(
            "Saved protected selection; selected count: \(self.selectedItemCount, privacy: .public)"
        )
        if protectionEnabled { ShieldManager.applySavedSelection() }
        if usageRemindersEnabled {
            refreshUsageReminderMonitoring()
        }
    }

    func savePhrase() {
        let savedPhrases = phrases.isEmpty
            ? ["I am making a bad choice"]
            : phrases
        phrase = savedPhrases.joined(separator: "\n")
        SharedSettings.phrases = savedPhrases
        OutLoudLog.challenge.debug(
            "Saved challenge phrases; count: \(savedPhrases.count, privacy: .public)"
        )
    }

    func setAcceptsSimilarAcknowledgements(_ enabled: Bool) {
        acceptsSimilarAcknowledgements = enabled
        SharedSettings.acceptsSimilarAcknowledgements = enabled
        OutLoudLog.challenge.info(
            "Flexible acknowledgement matching changed; enabled: \(enabled, privacy: .public)"
        )
        if enabled {
#if !targetEnvironment(simulator)
            Task { await FlexibleAcknowledgementMatcher.prepareModelAssets() }
#endif
        }
    }

    func returnDestination(for token: ApplicationToken) -> ReturnDestination? {
        returnMappings.first { $0.applicationToken == token }?.destination
    }

    func returnDestinationForPendingChallenge() -> ReturnDestination? {
        guard case let .application(token) = pendingChallenge else { return nil }
        return returnDestination(for: token)
    }

    func setReturnDestination(_ destination: ReturnDestination, for token: ApplicationToken) {
        if let index = returnMappings.firstIndex(where: { $0.applicationToken == token }) {
            returnMappings[index].destination = destination
        } else {
            returnMappings.append(
                ApplicationReturnMapping(applicationToken: token, destination: destination)
            )
        }
        SharedSettings.returnMappings = returnMappings
        OutLoudLog.screenTime.info(
            "Saved automatic return destination: \(destination.displayName, privacy: .public)"
        )
        if usageRemindersEnabled {
            refreshUsageReminderMonitoring()
        }
    }

    func setProtection(_ enabled: Bool) {
        protectionEnabled = enabled
        OutLoudLog.screenTime.info("Protection changed; enabled: \(enabled, privacy: .public)")
        guard !isDemoMode else { return }
        SharedSettings.protectionEnabled = enabled
        enabled ? ShieldManager.applySavedSelection() : ShieldManager.clear()
        if enabled {
            Task {
                _ = await requestFallbackNotificationAuthorization()
            }
        }
    }

    func setGracePeriod(_ seconds: TimeInterval) {
        gracePeriod = seconds
        SharedSettings.gracePeriod = seconds
        OutLoudLog.screenTime.debug("Access window changed; seconds: \(seconds, privacy: .public)")
    }

    func setAskAgainMode(_ mode: AskAgainMode) {
        askAgainMode = mode
        SharedSettings.askAgainMode = mode
        OutLoudLog.screenTime.info("Ask-again mode changed: \(mode.rawValue, privacy: .public)")
    }

    func selectUsageReminderInterval(_ interval: UsageReminderInterval) async {
        let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        )) ?? false
        guard allowed else {
            errorMessage = "Notifications are turned off. Allow notifications for OutLoud in Settings to use usage reminders."
            return
        }

        usageReminderInterval = interval
        usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = interval
        SharedSettings.usageRemindersEnabled = true
        OutLoudLog.screenTime.info(
            "Usage reminders enabled; minutes: \(interval.rawValue, privacy: .public)"
        )
        guard !isDemoMode else { return }

        do {
            try UsageReminderManager.refreshMonitoring()
        } catch {
            usageRemindersEnabled = false
            SharedSettings.usageRemindersEnabled = false
            errorMessage = "OutLoud couldn’t start usage reminders. \(error.localizedDescription)"
        }
    }

    func turnOffUsageReminders() {
        usageRemindersEnabled = false
        SharedSettings.usageRemindersEnabled = false
        UsageReminderManager.stopMonitoring()
        SharedSettings.usageReminderTargets = []
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [UsageReminderNotification.identifier]
        )
        OutLoudLog.screenTime.info("Usage reminders turned off")
    }

    func moveOnboarding(to step: OnboardingStep) {
        onboardingStep = step
        SharedSettings.onboardingStep = step.rawValue
        OutLoudLog.onboarding.info("Moved to onboarding step: \(step.rawValue, privacy: .public)")
    }

    func finishOnboarding(enableProtection: Bool = true) {
        savePhrase()
        setProtection(enableProtection)
        onboardingCompleted = true
        onboardingStep = .welcome
        SharedSettings.onboardingCompleted = true
        SharedSettings.onboardingStep = 0
        OutLoudLog.onboarding.info(
            "Onboarding completed; protection enabled: \(enableProtection, privacy: .public), usage reminders enabled: \(self.usageRemindersEnabled, privacy: .public)"
        )
    }

    func refreshPendingChallenge() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        if let expiration = SharedSettings.unlockExpiration, expiration <= Date() {
            OutLoudLog.screenTime.info("Expired access window found while app became active; reapplying shields")
            SharedSettings.unlockExpiration = nil
            ShieldManager.applySavedSelection()
        }
        if let pending = SharedSettings.pendingChallenge {
            challengeSessionID = SharedSettings.challengeRequestID ?? UUID()
            pendingChallenge = pending
            OutLoudLog.challenge.info(
                "Restored pending challenge; kind: \(pending.logName, privacy: .public)"
            )
        } else if SharedSettings.challengeRequested {
            // Fall back to releasing the complete saved selection when the
            // originating Screen Time token could not be restored.
            challengeSessionID = SharedSettings.challengeRequestID ?? UUID()
            pendingChallenge = .selection
            OutLoudLog.challenge.notice("Restored pending challenge through selection fallback")
        }
    }

    func beginPractice() {
        savePhrase()
        SharedSettings.pendingChallenge = nil
        challengeSessionID = UUID()
        pendingChallenge = .practice
        OutLoudLog.challenge.info("Practice challenge started")
    }

    func completeChallenge() -> Bool {
        guard let challenge = pendingChallenge else { return false }
        SharedSettings.pendingChallenge = nil
        OutLoudLog.challenge.info(
            "Completing challenge; kind: \(challenge.logName, privacy: .public)"
        )

        guard challenge != .practice else {
            OutLoudLog.challenge.info("Practice challenge completed")
            return true
        }

        let center = DeviceActivityCenter()
        center.stopMonitoring([SharedSettings.relockActivity])

        let calendar = Calendar.current
        let now = Date()
        // Every Visit normally re-arms sooner through Shortcuts. Keep the
        // original 15-minute window as a fallback if that automation is absent.
        let accessWindowDuration = askAgainMode.accessWindowDuration(timerDuration: gracePeriod)
        let schedule = DeviceActivitySchedule(
            intervalStart: scheduleComponents(for: now.addingTimeInterval(-1), calendar: calendar),
            intervalEnd: scheduleComponents(for: now.addingTimeInterval(accessWindowDuration), calendar: calendar),
            repeats: false
        )

        do {
            try center.startMonitoring(SharedSettings.relockActivity, during: schedule)
            SharedSettings.unlockExpiration = now.addingTimeInterval(accessWindowDuration)
            ShieldManager.release(challenge)
            OutLoudLog.screenTime.info(
                "Access window started; seconds: \(accessWindowDuration, privacy: .public), challenge kind: \(challenge.logName, privacy: .public)"
            )
            return true
        } catch {
            SharedSettings.unlockExpiration = nil
            ShieldManager.applySavedSelection()
            OutLoudLog.screenTime.error(
                "Failed to start access window: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = "OutLoud couldn’t create the access window. \(error.localizedDescription)"
            return false
        }
    }

    func dismissChallenge() {
        OutLoudLog.challenge.debug("Challenge screen dismissed")
        pendingChallenge = nil
    }

    func cancelChallenge() {
        OutLoudLog.challenge.info("Challenge cancelled")
        SharedSettings.pendingChallenge = nil
        pendingChallenge = nil
    }

    private func scheduleComponents(for date: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    private func pruneReturnMappings() {
        let selectedTokens = selection.applicationTokens
        returnMappings.removeAll { !selectedTokens.contains($0.applicationToken) }
        SharedSettings.returnMappings = returnMappings
    }

    private func refreshUsageReminderMonitoring() {
        do {
            try UsageReminderManager.refreshMonitoring()
        } catch {
            usageRemindersEnabled = false
            SharedSettings.usageRemindersEnabled = false
            errorMessage = "OutLoud couldn’t update usage reminders. \(error.localizedDescription)"
        }
    }

    private func requestFallbackNotificationAuthorization() async -> Bool {
#if compiler(>=6.3)
        if #available(iOS 26.5, *) {
            // The shield can open OutLoud directly on current iOS releases.
            return true
        }
#endif
        return (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

extension AuthorizationStatus {
    var grantsOutLoudScreenTimeAccess: Bool {
        if self == .approved { return true }
#if compiler(>=6.3)
        if #available(iOS 26.4, *), self == .approvedWithDataAccess {
            return true
        }
#endif
        return false
    }
}

private extension FamilyControlsError {
    var isTransientAuthorizationFailure: Bool {
        switch self {
        case .networkError, .unavailable:
            return true
        default:
            return false
        }
    }

    var outLoudAuthorizationMessage: String {
        switch self {
        case .authenticationMethodUnavailable:
            return "A device passcode is required for Screen Time access. Set a passcode in Settings, then try again."
        case .invalidAccountType:
            return "Screen Time access requires a valid Apple Account on this device. Check Settings, then try again."
        case .authorizationConflict:
            return "Another app already controls Screen Time on this device. Turn off its access in Settings, then try again."
        case .restricted:
            return "Screen Time access is restricted on this device. Check Screen Time settings, then try again."
        case .networkError, .unavailable:
            return "Screen Time is temporarily unavailable. Check the internet connection and try again."
        case .authorizationCanceled:
            return "Screen Time access wasn’t allowed. Tap Allow access to try again."
        case .invalidArgument:
            return "Screen Time access couldn’t be set up. Tap Allow access to try again."
#if compiler(>=6.3)
        case .unauthorized:
            return "Screen Time didn’t authorize OutLoud. Tap Allow access to try again."
#endif
        @unknown default:
            return "Screen Time access couldn’t be set up. Tap Allow access to try again."
        }
    }
}
