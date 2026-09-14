import Combine
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
    @Published var challengeMode: ChallengeMode
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
    @Published var hapticsEnabled: Bool
    @Published var isNotificationAuthorized = true
    @Published private(set) var isRequestingScreenTimeAuthorization = false
    @Published private(set) var isFinishingOnboarding = false
    @Published var errorMessage: String?
    @Published private(set) var challengeErrorMessage: String?
    @Published var demoSelectedApps: Set<String> = ["Instagram", "TikTok"]
    private var authorizationObservation: AnyCancellable?
    private let demoModeOverride: Bool?

    init(demoMode: Bool? = nil) {
        demoModeOverride = demoMode
        selection = SharedSettings.selection
        phrase = SharedSettings.phrases.joined(separator: "\n")
        acceptsSimilarAcknowledgements = SharedSettings.acceptsSimilarAcknowledgements
        challengeMode = SharedSettings.challengeMode
        protectionEnabled = SharedSettings.protectionEnabled
        askAgainMode = SharedSettings.askAgainMode
        gracePeriod = SharedSettings.gracePeriod
        pendingChallenge = SharedSettings.pendingChallenge
            ?? (SharedSettings.challengeRequested ? .selection : nil)
        challengeSessionID = SharedSettings.challengeRequestID ?? UUID()
        authorizationStatus = ScreenTimeAuthorizationClient.current.status()
        onboardingCompleted = SharedSettings.onboardingCompleted
        onboardingStep = OnboardingStep(storedValue: SharedSettings.onboardingStep)
        returnMappings = SharedSettings.returnMappings
        usageRemindersEnabled = SharedSettings.usageRemindersEnabled
        usageReminderInterval = SharedSettings.usageReminderInterval
        hapticsEnabled = SharedSettings.hapticsEnabled

        OutLoudLog.lifecycle.info(
            "Model initialized; onboarding complete: \(self.onboardingCompleted, privacy: .public), protection enabled: \(self.protectionEnabled, privacy: .public), selected count: \(self.selectedItemCount, privacy: .public)"
        )
        if !isDemoMode {
            authorizationObservation = ScreenTimeAuthorizationClient.current.observe { [weak self] status in
                self?.updateAuthorizationStatus(status)
            }
        }
        Task { await checkNotificationAuthorization() }
        if acceptsSimilarAcknowledgements {
#if !targetEnvironment(simulator)
            Task { await FlexibleAcknowledgementMatcher.prepareModel() }
#endif
        }
        if usageRemindersEnabled && isAuthorized && !isDemoMode {
            do {
                try UsageReminderManager.ensureMonitoring()
            } catch {
                OutLoudLog.screenTime.error(
                    "Failed to restore usage reminder monitoring: \(error.localizedDescription)"
                )
            }
        }
        if isAuthorized && !protectionEnabled && onboardingCompleted {
            ProtectionReminderManager.ensureRemindersScheduled(from: SharedSettings.protectionDisabledDate)
        }
    }

    var isDemoMode: Bool {
        if let demoModeOverride { return demoModeOverride }
#if targetEnvironment(simulator)
        return true
#else
        return ProcessInfo.processInfo.arguments.contains("--demo")
#endif
    }

    var isAuthorized: Bool {
        isDemoMode || authorizationStatus.grantsOutLoudScreenTimeAccess
    }

    var isProtectionActive: Bool { protectionEnabled && isAuthorized }

    var needsIndividualSelection: Bool { !selection.categoryTokens.isEmpty }

    static let individualSelectionMessage = "Choose individual apps or websites instead of whole categories so each unlock applies to just one item."

    var challengeRecoveryMessage: String? {
        guard let challenge = pendingChallenge, challenge != .practice else { return nil }
        if challenge == .selection {
            return "OutLoud couldn’t identify the app. Return to its shield and tap Unlock App again. Your apps are still protected."
        }
        if !challenge.isIndividual || needsIndividualSelection {
            return Self.individualSelectionMessage + " Return to OutLoud and update Apps. Your apps are still protected."
        }
        return nil
    }

    func updateAuthorizationStatus(_ status: AuthorizationStatus) {
        authorizationStatus = status
        guard !isDemoMode else { return }
        if status.grantsOutLoudScreenTimeAccess, SharedSettings.protectionEnabled {
            // Authorization can resolve after the first foreground refresh.
            ShieldManager.applySavedSelection()
        }
        guard status == .denied else { return }
        // Apple invalidates previously issued selection tokens on revocation.
        protectionEnabled = false
        SharedSettings.protectionEnabled = false
        AccessWindowManager.clear()
        ShieldManager.clear()
        cancelChallenge()
        selection = FamilyActivitySelection()
        SharedSettings.selection = selection
        returnMappings = []
        SharedSettings.returnMappings = []
        turnOffUsageReminders()
        SharedSettings.usageReminderTargets = []
        SharedSettings.everyVisitAutomationConfirmed = false
        askAgainMode = .afterTime
        SharedSettings.askAgainMode = .afterTime
        ProtectionReminderManager.cancelReminders()
    }

    var phrases: [String] {
        PhraseMatcher.phrases(from: phrase)
    }

    var responseStyleSummary: String {
        if acceptsSimilarAcknowledgements { return "Own words" }
        let savedPhrases = phrases
        return savedPhrases.count == 1 ? "1 phrase" : "\(savedPhrases.count) phrases"
    }

    var phraseSummary: String {
        "\(challengeMode.title) · \(responseStyleSummary)"
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

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard !isRequestingScreenTimeAuthorization else { return false }
        isRequestingScreenTimeAuthorization = true
        errorMessage = nil
        defer { isRequestingScreenTimeAuthorization = false }
        if !isDemoMode { updateAuthorizationStatus(ScreenTimeAuthorizationClient.current.status()) }

        OutLoudLog.onboarding.info("Requesting Screen Time authorization")
        for attempt in 0...1 {
            do {
                if !isDemoMode && !isAuthorized {
                    try await ScreenTimeAuthorizationClient.current.request()
                    authorizationStatus = ScreenTimeAuthorizationClient.current.status()
                }

                guard isAuthorized else {
                    OutLoudLog.onboarding.error(
                        "Screen Time authorization returned without an approved status; status: \(self.authorizationStatus.description, privacy: .public)"
                    )
                    errorMessage = "Screen Time access didn’t finish setting up. Tap Allow access to try again."
                    return false
                }

                let notificationsAllowed = await requestFallbackNotificationAuthorization()
                guard notificationsAllowed else {
                    OutLoudLog.onboarding.error("Notification authorization was denied during setup")
                    errorMessage = "Notifications are required to unlock your apps. Please allow notifications for OutLoud in Settings."
                    return false
                }
                if !isDemoMode { updateAuthorizationStatus(ScreenTimeAuthorizationClient.current.status()) }
                guard isAuthorized else {
                    errorMessage = "Screen Time access changed during setup. Restore access and choose your apps again."
                    return false
                }
                OutLoudLog.onboarding.info(
                    "Screen Time authorization finished; approved: true, notifications allowed: true"
                )
                return true
            } catch let familyControlsError as FamilyControlsError {
                authorizationStatus = ScreenTimeAuthorizationClient.current.status()
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
                return false
            } catch {
                authorizationStatus = ScreenTimeAuthorizationClient.current.status()
                OutLoudLog.onboarding.error(
                    "Screen Time authorization failed: \(error.localizedDescription, privacy: .public)"
                )
                errorMessage = "Screen Time access couldn’t be set up. Tap Allow access to try again."
                return false
            }
        }
        return false
    }

    func saveSelection() {
        guard !isDemoMode else {
            OutLoudLog.screenTime.debug(
                "Updated simulator selection; selected count: \(self.selectedItemCount, privacy: .public)"
            )
            return
        }
        guard !needsIndividualSelection else {
            selection = SharedSettings.selection
            errorMessage = Self.individualSelectionMessage
            return
        }
        if selection != SharedSettings.selection && askAgainMode == .everyVisit {
            // Shortcuts keeps its own app list. Changing ours requires setup again.
            SharedSettings.everyVisitAutomationConfirmed = false
            setAskAgainMode(.afterTime)
            errorMessage = "Your app selection changed. Timer mode is on until you update and confirm the Every visit automation."
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
            Task { await FlexibleAcknowledgementMatcher.prepareModel() }
#endif
        }
    }

    func setChallengeMode(_ mode: ChallengeMode) {
        challengeMode = mode
        SharedSettings.challengeMode = mode
        OutLoudLog.challenge.info(
            "Challenge mode changed: \(mode.rawValue, privacy: .public)"
        )
    }

    func returnDestination(for token: ApplicationToken) -> ReturnDestination? {
        returnMappings.first { $0.applicationToken == token }?.destination
    }

    func returnDestinationForPendingChallenge() -> ReturnDestination? {
        guard case let .application(token) = pendingChallenge else { return nil }
        return returnDestination(for: token)
    }

    func setReturnDestination(_ destination: ReturnDestination?, for token: ApplicationToken) {
        returnMappings.removeAll { $0.applicationToken == token }
        if let destination {
            returnMappings.append(
                ApplicationReturnMapping(applicationToken: token, destination: destination)
            )
        }
        SharedSettings.returnMappings = returnMappings
        OutLoudLog.screenTime.info(
            "Saved return destination: \(destination?.displayName ?? "manual", privacy: .public)"
        )
        if usageRemindersEnabled {
            refreshUsageReminderMonitoring()
        }
    }

    func enableProtectionWithAuthorizationCheck() async {
        guard !isDemoMode else {
            setProtection(true)
            return
        }
        guard await requestAuthorization() else { return }
        guard selectedItemCount > 0 else {
            errorMessage = "Choose your apps again after restoring Screen Time access."
            return
        }
        guard !needsIndividualSelection else {
            errorMessage = Self.individualSelectionMessage
            return
        }
        setProtection(true)
    }

    func setProtection(_ enabled: Bool) {
        guard !enabled || isAuthorized else {
            errorMessage = "Restore Screen Time access before turning on protection."
            return
        }
        guard !enabled || !needsIndividualSelection else {
            errorMessage = Self.individualSelectionMessage
            return
        }
        protectionEnabled = enabled
        OutLoudLog.screenTime.info("Protection changed; enabled: \(enabled, privacy: .public)")
        guard !isDemoMode else {
            if enabled {
                ProtectionReminderManager.cancelReminders()
            } else {
                ProtectionReminderManager.scheduleReminders()
            }
            return
        }
        SharedSettings.protectionEnabled = enabled
        cancelChallenge()
        AccessWindowManager.clear()
        enabled ? ShieldManager.applySavedSelection() : ShieldManager.clear()
        if enabled {
            SharedSettings.protectionDisabledDate = nil
            ProtectionReminderManager.cancelReminders()
            Task {
                _ = await requestFallbackNotificationAuthorization()
            }
        } else {
            if SharedSettings.protectionDisabledDate == nil {
                SharedSettings.protectionDisabledDate = ScreenTimeClient.current.now()
            }
            ProtectionReminderManager.scheduleReminders(from: SharedSettings.protectionDisabledDate)
        }
    }

    func setGracePeriod(_ seconds: TimeInterval) {
        gracePeriod = seconds
        SharedSettings.gracePeriod = seconds
        OutLoudLog.screenTime.debug("Access window changed; seconds: \(seconds, privacy: .public)")
    }

    func confirmEveryVisitAutomation() {
        SharedSettings.everyVisitAutomationConfirmed = true
        setAskAgainMode(.everyVisit)
    }

    func setAskAgainMode(_ mode: AskAgainMode) {
        let mode: AskAgainMode = mode == .everyVisit && !SharedSettings.everyVisitAutomationConfirmed
            ? .afterTime : mode
        askAgainMode = mode
        SharedSettings.askAgainMode = mode
        // A mode change should not leave a window with the previous timing rules.
        if !isDemoMode {
            AccessWindowManager.clear()
            ShieldManager.applySavedSelection()
        }
        OutLoudLog.screenTime.info("Ask-again mode changed: \(mode.rawValue, privacy: .public)")
    }

    func selectUsageReminderInterval(_ interval: UsageReminderInterval) async {
        errorMessage = nil
        let allowed = await NotificationPermissionClient.request()
        isNotificationAuthorized = allowed
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
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [UsageReminderNotification.identifier]
        )
        OutLoudLog.screenTime.info("Usage reminders turned off")
    }

    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
        SharedSettings.hapticsEnabled = enabled
        OutLoudLog.lifecycle.info("Haptics changed; enabled: \(enabled, privacy: .public)")
    }

    func moveOnboarding(to step: OnboardingStep) {
        onboardingStep = step
        SharedSettings.onboardingStep = step.rawValue
        OutLoudLog.onboarding.info("Moved to onboarding step: \(step.rawValue, privacy: .public)")
    }

    func finishOnboarding(enableProtection: Bool = true) async {
        guard !isFinishingOnboarding else { return }
        isFinishingOnboarding = true
        errorMessage = nil
        defer { isFinishingOnboarding = false }

        // Permissions may have changed since the first setup page, including
        // when resuming a previously unfinished onboarding session.
        if enableProtection {
            guard await requestAuthorization() else { return }
            guard selectedItemCount > 0, !needsIndividualSelection else {
                errorMessage = Self.individualSelectionMessage
                return
            }
        }
        savePhrase()
        SharedSettings.askAgainMode = askAgainMode
        onboardingCompleted = true
        onboardingStep = .welcome
        SharedSettings.onboardingCompleted = true
        SharedSettings.onboardingStep = 0
        setProtection(enableProtection)
        OutLoudLog.onboarding.info(
            "Onboarding completed; protection enabled: \(enableProtection, privacy: .public), usage reminders enabled: \(self.usageRemindersEnabled, privacy: .public)"
        )
    }

    func refreshPendingChallenge() {
        updateAuthorizationStatus(ScreenTimeAuthorizationClient.current.status())
        if !isDemoMode {
            protectionEnabled = SharedSettings.protectionEnabled
            if isAuthorized { ShieldManager.applySavedSelection() }
        }
        Task { await checkNotificationAuthorization() }
        if usageRemindersEnabled && isAuthorized && !isDemoMode {
            try? UsageReminderManager.ensureMonitoring()
        }
        if isAuthorized && !protectionEnabled && onboardingCompleted {
            ProtectionReminderManager.ensureRemindersScheduled(from: SharedSettings.protectionDisabledDate)
        } else if protectionEnabled {
            ProtectionReminderManager.cancelReminders()
        }
        if SharedSettings.accessWindows.contains(where: { $0.expiration <= ScreenTimeClient.current.now() })
            || (SharedSettings.unlockExpiration.map { $0 <= ScreenTimeClient.current.now() } ?? false) {
            OutLoudLog.screenTime.info("Expired access window found while app became active; reapplying shields")
            AccessWindowManager.expire()
        }
        if let pending = SharedSettings.pendingChallenge {
            let requestID = SharedSettings.challengeRequestID ?? UUID()
            if challengeSessionID != requestID { challengeErrorMessage = nil }
            challengeSessionID = requestID
            pendingChallenge = pending
            OutLoudLog.challenge.info(
                "Restored pending challenge; kind: \(pending.logName, privacy: .public)"
            )
        } else if SharedSettings.challengeRequested {
            // Preserve an unresolved handoff for recovery UI, never a broad unlock.
            let requestID = SharedSettings.challengeRequestID ?? UUID()
            if challengeSessionID != requestID { challengeErrorMessage = nil }
            challengeSessionID = requestID
            pendingChallenge = .selection
            OutLoudLog.challenge.notice("Restored pending challenge through selection fallback")
        } else {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: ["outloud.pending-challenge"]
            )
        }
    }

    func refreshAfterProtectionAction(error: String?) {
        // Lock actions cancel the shared handoff. Remove this process's completed
        // challenge screen ("Unlocked") and show any permission error on Home.
        dismissChallenge()
        refreshPendingChallenge()
        errorMessage = error
    }

    func beginPractice() {
        challengeErrorMessage = nil
        savePhrase()
        SharedSettings.pendingChallenge = nil
        challengeSessionID = UUID()
        pendingChallenge = .practice
        OutLoudLog.challenge.info("Practice challenge started")
    }

    func completeChallenge(expectedSessionID: UUID? = nil) -> Bool {
        guard expectedSessionID == nil || expectedSessionID == challengeSessionID,
              let challenge = pendingChallenge else { return false }
        challengeErrorMessage = nil
        OutLoudLog.challenge.info(
            "Completing challenge; kind: \(challenge.logName, privacy: .public)"
        )

        guard challenge != .practice else {
            SharedSettings.pendingChallenge = nil
            OutLoudLog.challenge.info("Practice challenge completed")
            return true
        }

        guard isDemoMode || ScreenTimeAuthorizationClient.current.status().grantsOutLoudScreenTimeAccess else {
            challengeErrorMessage = "Screen Time access is required. Close this pause and restore access in OutLoud."
            return false
        }
        guard challenge.isIndividual else {
            challengeErrorMessage = challenge == .selection
                ? "OutLoud couldn’t identify the app. Close this pause and tap Unlock App on its shield again."
                : Self.individualSelectionMessage + " Close this pause and update Apps in OutLoud."
            ShieldManager.applySavedSelection()
            return false
        }
        guard SharedSettings.selection.categoryTokens.isEmpty else {
            challengeErrorMessage = Self.individualSelectionMessage
            return false
        }

        let calendar = Calendar.current
        let now = ScreenTimeClient.current.now()
        // Every Visit normally re-arms sooner through Shortcuts. Keep the
        // original 15-minute window as a fallback if that automation is absent.
        let accessWindowDuration = askAgainMode.accessWindowDuration(timerDuration: gracePeriod)
        // DeviceActivity schedules have whole-second precision. Persist the
        // same deadline so its end callback cannot arrive before our deadline.
        let expiration = Date(timeIntervalSince1970:
            floor(now.addingTimeInterval(accessWindowDuration).timeIntervalSince1970))
        let schedule = DeviceActivitySchedule(
            intervalStart: scheduleComponents(for: now.addingTimeInterval(-1), calendar: calendar),
            intervalEnd: scheduleComponents(for: expiration, calendar: calendar),
            repeats: false
        )

        do {
            let window = AccessWindow(id: UUID(), challenge: challenge, expiration: expiration)
            try ScreenTimeClient.current.start(window.activity, schedule, [:])
            let replaced = SharedSettings.accessWindows.filter { $0.challenge == challenge }
            SharedSettings.accessWindows.removeAll { $0.challenge == challenge }
            SharedSettings.accessWindows.append(window)
            if !replaced.isEmpty { ScreenTimeClient.current.stop(replaced.map(\.activity)) }
            SharedSettings.unlockExpiration = nil
            ShieldManager.applySavedSelection()
            SharedSettings.pendingChallenge = nil
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: ["outloud.pending-challenge"]
            )
            OutLoudLog.screenTime.info(
                "Access window started; seconds: \(accessWindowDuration, privacy: .public), challenge kind: \(challenge.logName, privacy: .public)"
            )
            return true
        } catch {
            ShieldManager.applySavedSelection()
            OutLoudLog.screenTime.error(
                "Failed to start access window: \(error.localizedDescription, privacy: .public)"
            )
            challengeErrorMessage = "Your phrase was accepted, but OutLoud couldn’t unlock the app. Try unlocking again. \(error.localizedDescription)"
            return false
        }
    }

    func dismissChallenge() {
        challengeErrorMessage = nil
        OutLoudLog.challenge.debug("Challenge screen dismissed")
        pendingChallenge = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["outloud.pending-challenge"]
        )
    }

    func cancelChallenge() {
        challengeErrorMessage = nil
        OutLoudLog.challenge.info("Challenge cancelled")
        SharedSettings.pendingChallenge = nil
        pendingChallenge = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["outloud.pending-challenge"]
        )
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
        guard NotificationPermissionClient.requiresFallback() else {
            return true
        }
        let allowed = await NotificationPermissionClient.request()
        isNotificationAuthorized = allowed
        return allowed
    }

    func checkNotificationAuthorization() async {
        guard !isDemoMode else {
            isNotificationAuthorized = true
            return
        }
        isNotificationAuthorized = await NotificationPermissionClient.check()
    }
}

enum NotificationPermissionClient {
    static let live: () async -> Bool = {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .timeSensitive])) ?? false
    }
    static var request = live

    static let liveCheck: () async -> Bool = {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus != .denied
    }
    static var check = liveCheck

    static let liveRequiresFallback: () -> Bool = {
#if compiler(>=6.3)
        if #available(iOS 26.5, *) {
            return false
        }
#endif
        return true
    }
    static var requiresFallback = liveRequiresFallback
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
