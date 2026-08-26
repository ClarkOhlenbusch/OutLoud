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

    private enum Key {
        static let selection = "selection"
        static let phrase = "phrase"
        static let phrases = "phrases"
        static let acceptsSimilarAcknowledgements = "acceptsSimilarAcknowledgements"
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
    }

    static var defaults: UserDefaults {
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

    static var protectionEnabled: Bool {
        get { defaults.object(forKey: Key.protectionEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.protectionEnabled) }
    }

    static var askAgainMode: AskAgainMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.askAgainMode) else {
                return .everyVisit
            }
            return AskAgainMode(rawValue: rawValue) ?? .everyVisit
        }
        set { defaults.set(newValue.rawValue, forKey: Key.askAgainMode) }
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

    private static var pendingChallengeURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(pendingChallengeFilename, isDirectory: false)
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

        let today = Calendar.current.startOfDay(for: Date())
        let previousTargets = SharedSettings.usageReminderTargets
        let targets = selectedChallenges().map { challenge in
            let previous = previousTargets.first { $0.challenge == challenge }
            return UsageReminderTarget(
                id: previous?.id ?? UUID(),
                challenge: challenge,
                appName: appName(for: challenge),
                elapsedMinutes: 0,
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

        let center = DeviceActivityCenter()
        let activeNames = Set(center.activities)
        if SharedSettings.usageReminderTargets.isEmpty {
            try refreshMonitoring()
            return
        }

        for target in SharedSettings.usageReminderTargets
        where !activeNames.contains(target.activityName) {
            try startMonitoring(target)
        }
    }

    static func stopMonitoring() {
        let center = DeviceActivityCenter()
        let names = Set(
            center.activities.filter(UsageReminderActivity.isUsageReminder)
                + SharedSettings.usageReminderTargets.map(\.activityName)
        )
        if !names.isEmpty {
            center.stopMonitoring(Array(names))
        }
    }

    static func target(for activity: DeviceActivityName) -> UsageReminderTarget? {
        SharedSettings.usageReminderTargets.first { $0.activityName == activity }
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

        let expectedMinutes = targets[index].elapsedMinutes
            + SharedSettings.usageReminderInterval.rawValue
        guard elapsedMinutes == expectedMinutes else { return nil }

        let previousActivity = targets[index].activityName
        targets[index].elapsedMinutes = elapsedMinutes
        targets[index].generation += 1
        SharedSettings.usageReminderTargets = targets

        DeviceActivityCenter().stopMonitoring([previousActivity])
        try startMonitoring(targets[index])
        return targets[index]
    }

    static func resetForNewDayIfNeeded(activity: DeviceActivityName) throws {
        guard SharedSettings.usageRemindersEnabled else { return }
        var targets = SharedSettings.usageReminderTargets
        guard let index = targets.firstIndex(where: { $0.activityName == activity }) else {
            return
        }

        let today = Calendar.current.startOfDay(for: Date())
        guard targets[index].dayStarted < today else { return }

        let previousActivity = targets[index].activityName
        targets[index].elapsedMinutes = 0
        targets[index].generation += 1
        targets[index].dayStarted = today
        SharedSettings.usageReminderTargets = targets

        DeviceActivityCenter().stopMonitoring([previousActivity])
        try startMonitoring(targets[index])
    }

    private static func startMonitoring(_ target: UsageReminderTarget) throws {
        let interval = SharedSettings.usageReminderInterval.rawValue
        let nextElapsedMinutes = target.elapsedMinutes + interval
        let event: DeviceActivityEvent

        switch target.challenge {
        case .application(let token):
            event = makeEvent(applications: [token], thresholdMinutes: interval)
        case .category(let token):
            event = makeEvent(categories: [token], thresholdMinutes: interval)
        case .webDomain(let token):
            event = makeEvent(webDomains: [token], thresholdMinutes: interval)
        case .selection, .practice:
            return
        }

        try DeviceActivityCenter().startMonitoring(
            target.activityName,
            during: schedule,
            events: [UsageReminderEvent.name(for: nextElapsedMinutes): event]
        )
    }

    private static func makeEvent(
        applications: Set<ApplicationToken> = [],
        categories: Set<ActivityCategoryToken> = [],
        webDomains: Set<WebDomainToken> = [],
        thresholdMinutes: Int
    ) -> DeviceActivityEvent {
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(
                applications: applications,
                categories: categories,
                webDomains: webDomains,
                threshold: DateComponents(minute: thresholdMinutes),
                includesPastActivity: false
            )
        }
        return DeviceActivityEvent(
            applications: applications,
            categories: categories,
            webDomains: webDomains,
            threshold: DateComponents(minute: thresholdMinutes)
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
    static let body = "You asked OutLoud to interrupt you. Close it now."

    static func title(elapsedMinutes: Int, appName: String) -> String {
        let duration = elapsedMinutes == 1 ? "1 MINUTE" : "\(elapsedMinutes) MINUTES"
        return "YOU HAVE SPENT \(duration) ON \(appName.uppercased())"
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .tikTok: "TikTok"
        case .youTube: "YouTube"
        case .reddit: "Reddit"
        case .x: "X"
        }
    }

    var systemImageName: String {
        switch self {
        case .instagram: "camera.fill"
        case .tikTok: "music.note"
        case .youTube: "play.rectangle.fill"
        case .reddit: "bubble.left.and.bubble.right.fill"
        case .x: "textformat"
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
        }
        return values.compactMap(URL.init(string:))
    }
}

struct ApplicationReturnMapping: Codable, Equatable {
    let applicationToken: ApplicationToken
    var destination: ReturnDestination
}

extension PendingChallenge {
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
