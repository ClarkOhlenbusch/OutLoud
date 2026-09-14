import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog

enum OutLoudLog {
    private static let subsystem = "com.clarkohlenbusch.outloud"

    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    static let onboarding = Logger(subsystem: subsystem, category: "Onboarding")
    static let screenTime = Logger(subsystem: subsystem, category: "ScreenTime")
    static let challenge = Logger(subsystem: subsystem, category: "Challenge")
    static let speech = Logger(subsystem: subsystem, category: "Speech")
    static let shortcuts = Logger(subsystem: subsystem, category: "Shortcuts")
}

enum SharedSettings {
    static let appGroup = "group.com.clarkohlenbusch.outloud"
    static let storeName = ManagedSettingsStore.Name("outloud")
    static let relockActivity = DeviceActivityName("outloud.relock")
    private static let pendingChallengeFilename = "pending-challenge.json"

#if DEBUG
    // Each test uses its own suite and directory; never the user's App Group.
    static var testStorage: (defaults: UserDefaults, directory: URL)?
#endif

    private enum Key {
        static let selection = "selection"
        static let phrase = "phrase"
        static let phrases = "phrases"
        static let acceptsSimilarAcknowledgements = "acceptsSimilarAcknowledgements"
        static let challengeMode = "challengeMode"
        static let protectionEnabled = "protectionEnabled"
        static let askAgainMode = "askAgainMode"
        static let gracePeriod = "gracePeriod"
        static let pendingChallenge = "pendingChallenge"
        static let challengeRequestID = "challengeRequestID"
        static let challengeRequested = "challengeRequested"
        static let unlockExpiration = "unlockExpiration"
        static let onboardingCompleted = "onboardingCompleted"
        static let onboardingStep = "onboardingStep"
        static let returnMappings = "returnMappings"
        static let usageRemindersEnabled = "usageRemindersEnabled"
        static let usageReminderIntervalMinutes = "usageReminderIntervalMinutes"
        static let usageReminderTargets = "usageReminderTargets"
        static let hapticsEnabled = "hapticsEnabled"
        static let protectionDisabledDate = "protectionDisabledDate"
    }

    static var defaults: UserDefaults {
#if DEBUG
        if let testStorage { return testStorage.defaults }
#endif
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            preconditionFailure("The OutLoud App Group is missing from the target entitlements.")
        }
        return defaults
    }

    static var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: Key.selection),
                  let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
                return FamilyActivitySelection()
            }
            return value
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.selection)
        }
    }

    static var phrase: String {
        get { defaults.string(forKey: Key.phrase) ?? "I am making a bad choice" }
        set { defaults.set(newValue, forKey: Key.phrase) }
    }

    static var phrases: [String] {
        get {
            if let data = defaults.data(forKey: Key.phrases),
               let stored = try? JSONDecoder().decode([String].self, from: data),
               !stored.isEmpty {
                return stored
            }
            return [phrase]
        }
        set {
            let saved = newValue.isEmpty ? ["I am making a bad choice"] : newValue
            defaults.set(try? JSONEncoder().encode(saved), forKey: Key.phrases)
            // Keep the original key current for installs upgrading from the
            // single-phrase version and for older extensions during an update.
            phrase = saved[0]
        }
    }

    static var acceptsSimilarAcknowledgements: Bool {
        get { defaults.object(forKey: Key.acceptsSimilarAcknowledgements) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.acceptsSimilarAcknowledgements) }
    }

    static var challengeMode: ChallengeMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.challengeMode) else {
                return .speak
            }
            return ChallengeMode(rawValue: rawValue) ?? .speak
        }
        set { defaults.set(newValue.rawValue, forKey: Key.challengeMode) }
    }

    static var protectionEnabled: Bool {
        get { defaults.object(forKey: Key.protectionEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.protectionEnabled) }
    }

    static var protectionDisabledDate: Date? {
        get {
            guard let timeInterval = defaults.object(forKey: Key.protectionDisabledDate) as? Double else {
                return nil
            }
            return Date(timeIntervalSince1970: timeInterval)
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: Key.protectionDisabledDate)
            } else {
                defaults.removeObject(forKey: Key.protectionDisabledDate)
            }
        }
    }

    static var askAgainMode: AskAgainMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.askAgainMode),
                  let mode = AskAgainMode(rawValue: rawValue) else { return .afterTime }
            return mode == .everyVisit && !everyVisitAutomationConfirmed ? .afterTime : mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.askAgainMode) }
    }

    static var needsEveryVisitSetup: Bool {
        let storedMode = defaults.string(forKey: Key.askAgainMode)
        // Older installs defaulted to Every visit without writing a preference.
        let legacyEveryVisit = storedMode == AskAgainMode.everyVisit.rawValue
            || (storedMode == nil && onboardingCompleted)
        return legacyEveryVisit && !everyVisitAutomationConfirmed
    }

    static var everyVisitAutomationConfirmed: Bool {
        get { defaults.bool(forKey: "everyVisitAutomationConfirmed") }
        set { defaults.set(newValue, forKey: "everyVisitAutomationConfirmed") }
    }

    static var onboardingCompleted: Bool {
        get { defaults.bool(forKey: Key.onboardingCompleted) }
        set { defaults.set(newValue, forKey: Key.onboardingCompleted) }
    }

    static var onboardingStep: Int {
        get { defaults.integer(forKey: Key.onboardingStep) }
        set { defaults.set(newValue, forKey: Key.onboardingStep) }
    }

    static var gracePeriod: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.gracePeriod)
            return value >= 900 ? value : 900
        }
        set { defaults.set(newValue, forKey: Key.gracePeriod) }
    }

    static var pendingChallenge: PendingChallenge? {
        get {
            if let url = pendingChallengeURL,
               let data = try? Data(contentsOf: url) {
                if let envelope = try? JSONDecoder().decode(PendingChallengeEnvelope.self, from: data) {
                    return envelope.challenge
                }
                if let challenge = try? JSONDecoder().decode(PendingChallenge.self, from: data) {
                    return challenge
                }
            }

            guard let data = defaults.data(forKey: Key.pendingChallenge) else { return nil }
            return try? JSONDecoder().decode(PendingChallenge.self, from: data)
        }
        set {
            if let newValue {
                // The token is the preferred path because it lets OutLoud release
                // only the app that initiated the challenge. Keep a separate flag
                // because Screen Time tokens can occasionally fail to round-trip
                // between the shield extension and its containing app.
                defaults.set(true, forKey: Key.challengeRequested)
                let encodedChallenge = (try? JSONEncoder().encode(newValue))
                    ?? (try? JSONEncoder().encode(PendingChallenge.selection))
                let requestID = UUID()

                if let data = encodedChallenge {
                    defaults.set(data, forKey: Key.pendingChallenge)
                    defaults.set(requestID.uuidString, forKey: Key.challengeRequestID)
                    if let url = pendingChallengeURL {
                        let storableChallenge = (try? JSONDecoder().decode(PendingChallenge.self, from: data))
                            ?? .selection
                        let envelope = PendingChallengeEnvelope(
                            id: requestID,
                            challenge: storableChallenge
                        )
                        if let envelopeData = try? JSONEncoder().encode(envelope) {
                            do {
                                try envelopeData.write(to: url, options: .atomic)
                                OutLoudLog.challenge.debug(
                                    "Persisted challenge handoff; kind: \(storableChallenge.logName, privacy: .public)"
                                )
                            } catch {
                                OutLoudLog.challenge.error(
                                    "Failed to persist challenge handoff file: \(error.localizedDescription, privacy: .public)"
                                )
                            }
                        }
                    } else {
                        OutLoudLog.challenge.fault("App Group container unavailable while saving challenge handoff")
                    }
                } else {
                    OutLoudLog.challenge.error("Failed to encode pending challenge")
                    defaults.removeObject(forKey: Key.pendingChallenge)
                }
            } else {
                defaults.removeObject(forKey: Key.pendingChallenge)
                defaults.removeObject(forKey: Key.challengeRequestID)
                defaults.set(false, forKey: Key.challengeRequested)
                if let url = pendingChallengeURL {
                    try? FileManager.default.removeItem(at: url)
                }
                OutLoudLog.challenge.debug("Cleared pending challenge handoff")
            }

            // The shield and main app are separate processes. Flush this small
            // handoff before the notification can launch the main app.
            defaults.synchronize()
        }
    }

    static var challengeRequested: Bool {
        if let url = pendingChallengeURL, FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return defaults.bool(forKey: Key.challengeRequested)
    }

    static var challengeRequestID: UUID? {
        if let url = pendingChallengeURL,
           let data = try? Data(contentsOf: url),
           let envelope = try? JSONDecoder().decode(PendingChallengeEnvelope.self, from: data) {
            return envelope.id
        }

        guard let value = defaults.string(forKey: Key.challengeRequestID) else { return nil }
        return UUID(uuidString: value)
    }

    static var hasSharedContainer: Bool { pendingChallengeURL != nil }

    static var unlockExpiration: Date? {
        get { defaults.object(forKey: Key.unlockExpiration) as? Date }
        set { defaults.set(newValue, forKey: Key.unlockExpiration) }
    }

    static var accessWindows: [AccessWindow] {
        get {
            guard let data = defaults.data(forKey: "accessWindows") else { return [] }
            return (try? JSONDecoder().decode([AccessWindow].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "accessWindows") }
    }

    static var returnMappings: [ApplicationReturnMapping] {
        get {
            guard let data = defaults.data(forKey: Key.returnMappings) else { return [] }
            return (try? JSONDecoder().decode([ApplicationReturnMapping].self, from: data)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.returnMappings)
        }
    }

    static var usageRemindersEnabled: Bool {
        get { defaults.bool(forKey: Key.usageRemindersEnabled) }
        set { defaults.set(newValue, forKey: Key.usageRemindersEnabled) }
    }

    static var usageReminderInterval: UsageReminderInterval {
        get {
            let storedValue = defaults.integer(forKey: Key.usageReminderIntervalMinutes)
            return UsageReminderInterval(rawValue: storedValue) ?? .fiveMinutes
        }
        set { defaults.set(newValue.rawValue, forKey: Key.usageReminderIntervalMinutes) }
    }

    static var usageReminderTargets: [UsageReminderTarget] {
        get {
            guard let data = defaults.data(forKey: Key.usageReminderTargets) else { return [] }
            return (try? JSONDecoder().decode([UsageReminderTarget].self, from: data)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.usageReminderTargets)
        }
    }

    static var hapticsEnabled: Bool {
        get { defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.hapticsEnabled) }
    }

    private static var pendingChallengeURL: URL? {
#if DEBUG
        if let testStorage {
            return testStorage.directory.appendingPathComponent(pendingChallengeFilename)
        }
#endif
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(pendingChallengeFilename, isDirectory: false)
    }
}

enum ChallengeMode: String, CaseIterable, Codable, Identifiable {
    case speak
    case type
    case either

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speak: "Say out loud"
        case .type: "Type"
        case .either: "Say or type"
        }
    }

    var detail: String {
        switch self {
        case .speak: "Speak your acknowledgment or phrase out loud."
        case .type: "Type your acknowledgment or phrase."
        case .either: "Choose whether to speak or type each time."
        }
    }

    var icon: String {
        switch self {
        case .speak: "mic.fill"
        case .type: "keyboard.fill"
        case .either: "bubble.left.and.text.bubble.right.fill"
        }
    }
}

enum AskAgainMode: String {
    case everyVisit
    case afterTime

    func accessWindowDuration(timerDuration: TimeInterval) -> TimeInterval {
        switch self {
        case .everyVisit: 15 * 60
        case .afterTime: timerDuration
        }
    }
}

enum UsageReminderInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 1
    case fiveMinutes = 5
    case tenMinutes = 10

    var id: Int { rawValue }

    var title: String {
        rawValue == 1 ? "1 min" : "\(rawValue) min"
    }

    var summary: String {
        rawValue == 1 ? "Every minute" : "Every \(rawValue) min"
    }

    func nextNotificationMinute(after elapsedMinutes: Int) -> Int {
        let elapsedMinutes = max(0, elapsedMinutes)
        return ((elapsedMinutes / rawValue) + 1) * rawValue
    }
}

enum UsageReminderEvent {
    private static let prefix = "outloud.usage-reminder."

    static func name(for elapsedMinutes: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("\(prefix)\(elapsedMinutes)")
    }

    static func elapsedMinutes(from name: DeviceActivityEvent.Name) -> Int? {
        guard name.rawValue.hasPrefix(prefix) else { return nil }
        return Int(name.rawValue.dropFirst(prefix.count))
    }

    static func isExpected(
        _ elapsedMinutes: Int,
        after previousMinutes: Int,
        interval: UsageReminderInterval
    ) -> Bool {
        elapsedMinutes == interval.nextNotificationMinute(after: previousMinutes)
    }
}

struct UsageReminderTarget: Codable, Equatable {
    let id: UUID
    var challenge: PendingChallenge
    var appName: String
    var elapsedMinutes: Int
    var generation: Int
    var dayStarted: Date

    var activityName: DeviceActivityName {
        UsageReminderActivity.name(targetID: id, generation: generation)
    }
}

enum UsageReminderActivity {
    private static let prefix = "outloud.usage-reminder."

    static func name(targetID: UUID, generation: Int) -> DeviceActivityName {
        DeviceActivityName("\(prefix)\(targetID.uuidString).\(generation)")
    }

    static func isUsageReminder(_ name: DeviceActivityName) -> Bool {
        name.rawValue.hasPrefix(prefix)
    }
}

enum UsageReminderManager {
    static var schedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
    }

    static func refreshMonitoring() throws {
        stopMonitoring()

        let today = Calendar.current.startOfDay(for: ScreenTimeClient.current.now())
        let previousTargets = SharedSettings.usageReminderTargets
        let targets = selectedChallenges().map { challenge in
            let previous = previousTargets.first { $0.challenge == challenge }
            let elapsedMinutes: Int
            if let previous,
               Calendar.current.isDate(previous.dayStarted, inSameDayAs: today) {
                elapsedMinutes = previous.elapsedMinutes
            } else {
                elapsedMinutes = 0
            }
            return UsageReminderTarget(
                id: previous?.id ?? UUID(),
                challenge: challenge,
                appName: appName(for: challenge),
                elapsedMinutes: elapsedMinutes,
                generation: (previous?.generation ?? -1) + 1,
                dayStarted: today
            )
        }
        SharedSettings.usageReminderTargets = targets

        do {
            for target in targets {
                try startMonitoring(target)
            }
        } catch {
            stopMonitoring()
            SharedSettings.usageReminderTargets = []
            throw error
        }
    }

    static func ensureMonitoring() throws {
        guard SharedSettings.usageRemindersEnabled else {
            stopMonitoring()
            return
        }

        let today = Calendar.current.startOfDay(for: ScreenTimeClient.current.now())
        if SharedSettings.usageReminderTargets.isEmpty
            || SharedSettings.usageReminderTargets.contains(where: { $0.dayStarted < today }) {
            try refreshMonitoring()
            return
        }

        let activeNames = Set(ScreenTimeClient.current.activities())
        for target in SharedSettings.usageReminderTargets
        where !activeNames.contains(target.activityName) {
            try startMonitoring(target)
        }
    }

    static func stopMonitoring() {
        let names = Set(
            ScreenTimeClient.current.activities().filter(UsageReminderActivity.isUsageReminder)
                + SharedSettings.usageReminderTargets.map(\.activityName)
        )
        if !names.isEmpty {
            ScreenTimeClient.current.stop(Array(names))
        }
    }

    static func target(for activity: DeviceActivityName) -> UsageReminderTarget? {
        SharedSettings.usageReminderTargets.first { $0.activityName == activity }
    }

    /// The extension delegates its callback here so tests exercise filtering,
    /// notification delivery and monitor advancement as one production flow.
    static func handleThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName,
        notify: (Int, String) -> Void
    ) throws {
        guard UsageReminderActivity.isUsageReminder(activity),
              SharedSettings.usageRemindersEnabled,
              let minutes = UsageReminderEvent.elapsedMinutes(from: event),
              let target = target(for: activity) else { return }

        let today = Calendar.current.startOfDay(for: ScreenTimeClient.current.now())
        if target.dayStarted < today {
            // Recover from missed midnight rollover if device was asleep at 00:00.
            // Reset for today instead of delivering yesterday's stale threshold event.
            try resetForNewDayIfNeeded(activity: activity)
            return
        }

        guard UsageReminderEvent.isExpected(minutes, after: target.elapsedMinutes,
                                            interval: SharedSettings.usageReminderInterval) else { return }
        notify(minutes, target.appName)
        try advance(activity: activity, elapsedMinutes: minutes)
    }

    @discardableResult
    static func advance(
        activity: DeviceActivityName,
        elapsedMinutes: Int
    ) throws -> UsageReminderTarget? {
        guard SharedSettings.usageRemindersEnabled else { return nil }
        var targets = SharedSettings.usageReminderTargets
        guard let index = targets.firstIndex(where: { $0.activityName == activity }) else {
            return nil
        }

        guard UsageReminderEvent.isExpected(
            elapsedMinutes,
            after: targets[index].elapsedMinutes,
            interval: SharedSettings.usageReminderInterval
        ) else { return nil }

        let previousActivity = targets[index].activityName
        targets[index].elapsedMinutes = elapsedMinutes
        targets[index].generation += 1
        SharedSettings.usageReminderTargets = targets

        ScreenTimeClient.current.stop([previousActivity])
        try startMonitoring(targets[index])
        return targets[index]
    }

    static func resetForNewDayIfNeeded(activity: DeviceActivityName) throws {
        guard SharedSettings.usageRemindersEnabled else { return }
        var targets = SharedSettings.usageReminderTargets
        guard let index = targets.firstIndex(where: { $0.activityName == activity }) else {
            return
        }

        let today = Calendar.current.startOfDay(for: ScreenTimeClient.current.now())
        guard targets[index].dayStarted < today else { return }

        let previousActivity = targets[index].activityName
        targets[index].elapsedMinutes = 0
        targets[index].generation += 1
        targets[index].dayStarted = today
        SharedSettings.usageReminderTargets = targets

        ScreenTimeClient.current.stop([previousActivity])
        try startMonitoring(targets[index])
    }

    private static func startMonitoring(_ target: UsageReminderTarget) throws {
        let nextElapsedMinutes = SharedSettings.usageReminderInterval.nextNotificationMinute(
            after: target.elapsedMinutes
        )
        let event: DeviceActivityEvent

        switch target.challenge {
        case .application(let token):
            event = makeEvent(
                applications: [token],
                elapsedMinutes: target.elapsedMinutes,
                nextElapsedMinutes: nextElapsedMinutes
            )
        case .category(let token):
            event = makeEvent(
                categories: [token],
                elapsedMinutes: target.elapsedMinutes,
                nextElapsedMinutes: nextElapsedMinutes
            )
        case .webDomain(let token):
            event = makeEvent(
                webDomains: [token],
                elapsedMinutes: target.elapsedMinutes,
                nextElapsedMinutes: nextElapsedMinutes
            )
        case .selection, .practice:
            return
        }

        try ScreenTimeClient.current.start(
            target.activityName,
            schedule,
            [UsageReminderEvent.name(for: nextElapsedMinutes): event]
        )
    }

    private static func makeEvent(
        applications: Set<ApplicationToken> = [],
        categories: Set<ActivityCategoryToken> = [],
        webDomains: Set<WebDomainToken> = [],
        elapsedMinutes: Int,
        nextElapsedMinutes: Int
    ) -> DeviceActivityEvent {
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(
                applications: applications,
                categories: categories,
                webDomains: webDomains,
                threshold: DateComponents(minute: nextElapsedMinutes),
                includesPastActivity: true
            )
        }
        return DeviceActivityEvent(
            applications: applications,
            categories: categories,
            webDomains: webDomains,
            threshold: DateComponents(minute: nextElapsedMinutes - elapsedMinutes)
        )
    }

    private static func selectedChallenges() -> [PendingChallenge] {
        let selection = SharedSettings.selection
        return selection.applicationTokens.map(PendingChallenge.application)
            + selection.categoryTokens.map(PendingChallenge.category)
            + selection.webDomainTokens.map(PendingChallenge.webDomain)
    }

    private static func appName(for challenge: PendingChallenge) -> String {
        switch challenge {
        case .application(let token):
            return SharedSettings.returnMappings
                .first { $0.applicationToken == token }?
                .destination.displayName ?? "this app"
        case .category:
            return "selected apps"
        case .webDomain:
            return "this website"
        case .selection:
            return "your selected apps"
        case .practice:
            return "this app"
        }
    }
}

enum UsageReminderNotification {
    static let identifier = "outloud.usage-reminder"
    static let categoryIdentifier = "OUTLOUD_USAGE_REMINDER"
    static let lockActionIdentifier = "OUTLOUD_LOCK_NOW"
    static let body = "You asked OutLoud to interrupt you. Close it now."

    static func title(elapsedMinutes: Int, appName: String) -> String {
        let duration = elapsedMinutes == 1 ? "1 MINUTE" : "\(elapsedMinutes) MINUTES"
        let normalized = appName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized == "THIS APP" || normalized == "YOUR PROTECTED APP" {
            return "YOU HAVE SPENT \(duration) IN USE"
        }
        return "YOU HAVE SPENT \(duration) ON \(normalized)"
    }
}

enum ProtectionReminderNotification {
    static let identifierPrefix = "outloud.protection-reminder"
    static let categoryIdentifier = "OUTLOUD_PROTECTION_REMINDER"
    static let reenableActionIdentifier = "OUTLOUD_ENABLE_PROTECTION"

    static let standardOffsets: [TimeInterval] = [
        3600,       // 1 hour
        3 * 3600,   // 3 hours
        6 * 3600,   // 6 hours
        12 * 3600,  // 12 hours
        18 * 3600,  // 18 hours
        24 * 3600,  // 24 hours
        30 * 3600,  // 30 hours
        36 * 3600,  // 36 hours
        42 * 3600,  // 42 hours
        48 * 3600,  // 48 hours
        54 * 3600,  // 54 hours
        60 * 3600,  // 60 hours
        66 * 3600,  // 66 hours
        72 * 3600   // 72 hours
    ]

    static func identifier(for offset: TimeInterval) -> String {
        "\(identifierPrefix).\(Int(offset))"
    }

    static var allIdentifiers: [String] {
        standardOffsets.map { identifier(for: $0) }
    }

    static func isProtectionReminder(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    static func title(for offset: TimeInterval) -> String {
        let hours = Int(round(offset / 3600))
        if hours <= 1 {
            return "Protection is off"
        } else if hours == 3 {
            return "Still scrolling unprotected?"
        } else {
            return "Protection is still off"
        }
    }

    static func body(for offset: TimeInterval) -> String {
        let hours = Int(round(offset / 3600))
        if hours <= 1 {
            return "Protection is off. Turn it back on and stop doomscrolling like a loser."
        } else if hours == 3 {
            return "It’s been 3 hours without protection. Turn it back on and stop doomscrolling like a loser."
        } else if hours == 24 {
            return "A full day without protection. Turn it back on and stop doomscrolling like a loser."
        } else {
            return "It’s been \(hours) hours without protection. Turn it back on and stop doomscrolling like a loser."
        }
    }
}

private struct PendingChallengeEnvelope: Codable {
    let id: UUID
    let challenge: PendingChallenge
}

enum PendingChallenge: Codable, Equatable {
    case application(ApplicationToken)
    case category(ActivityCategoryToken)
    case webDomain(WebDomainToken)
    case selection
    case practice
}

enum ReturnDestination: String, CaseIterable, Codable, Identifiable {
    case instagram
    case tikTok
    case youTube
    case reddit
    case x
    case facebook
    case threads
    case snapchat
    case discord
    case netflix
    case safari

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .tikTok: "TikTok"
        case .youTube: "YouTube"
        case .reddit: "Reddit"
        case .x: "X"
        case .facebook: "Facebook"
        case .threads: "Threads"
        case .snapchat: "Snapchat"
        case .discord: "Discord"
        case .netflix: "Netflix"
        case .safari: "Safari"
        }
    }

    var systemImageName: String {
        switch self {
        case .instagram: "camera.fill"
        case .tikTok: "music.note"
        case .youTube: "play.rectangle.fill"
        case .reddit: "bubble.left.and.bubble.right.fill"
        case .x: "textformat"
        case .facebook: "person.2.fill"
        case .threads: "at"
        case .snapchat: "camera.viewfinder"
        case .discord: "bubble.left.and.exclamationmark.bubble.right.fill"
        case .netflix: "film.fill"
        case .safari: "safari.fill"
        }
    }

    var launchURLs: [URL] {
        let values: [String]
        switch self {
        case .instagram:
            values = ["instagram://app", "https://www.instagram.com/"]
        case .tikTok:
            values = ["snssdk1233://", "https://www.tiktok.com/"]
        case .youTube:
            values = ["youtube://", "https://www.youtube.com/"]
        case .reddit:
            values = ["reddit://", "https://www.reddit.com/"]
        case .x:
            values = ["twitter://", "https://x.com/"]
        case .facebook:
            values = ["fb://", "https://www.facebook.com/"]
        case .threads:
            values = ["barcelona://", "https://www.threads.net/"]
        case .snapchat:
            values = ["snapchat://", "https://www.snapchat.com/"]
        case .discord:
            values = ["discord://", "https://discord.com/"]
        case .netflix:
            values = ["nflx://", "https://www.netflix.com/"]
        case .safari:
            values = ["x-web-search://", "https://www.apple.com/safari/"]
        }
        return values.compactMap(URL.init(string:))
    }
}

struct ApplicationReturnMapping: Codable, Equatable {
    let applicationToken: ApplicationToken
    var destination: ReturnDestination
}

extension PendingChallenge {
    var isIndividual: Bool {
        switch self {
        case .application, .webDomain: true
        case .category, .selection, .practice: false
        }
    }

    var logName: String {
        switch self {
        case .application: "application"
        case .category: "category"
        case .webDomain: "web-domain"
        case .selection: "selection"
        case .practice: "practice"
        }
    }
}

extension FamilyActivitySelection {
    var selectedItemCount: Int {
        applicationTokens.count + categoryTokens.count + webDomainTokens.count
    }
}
