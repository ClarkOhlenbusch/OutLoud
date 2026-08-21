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
        static let protectionEnabled = "protectionEnabled"
        static let gracePeriod = "gracePeriod"
        static let pendingChallenge = "pendingChallenge"
        static let challengeRequestID = "challengeRequestID"
        static let challengeRequested = "challengeRequested"
        static let unlockExpiration = "unlockExpiration"
        static let onboardingCompleted = "onboardingCompleted"
        static let onboardingStep = "onboardingStep"
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
        get { defaults.string(forKey: Key.phrase) ?? "I am choosing to spend my time here" }
        set { defaults.set(newValue, forKey: Key.phrase) }
    }

    static var protectionEnabled: Bool {
        get { defaults.object(forKey: Key.protectionEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.protectionEnabled) }
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

    private static var pendingChallengeURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(pendingChallengeFilename, isDirectory: false)
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
