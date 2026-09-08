import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// The system boundary shared by the app and extensions. Tests supply an
/// in-memory monitor and shield store while exercising the production flows.
struct ScreenTimeClient {
    var now: () -> Date
    var activities: () -> [DeviceActivityName]
    var start: (DeviceActivityName, DeviceActivitySchedule, [DeviceActivityEvent.Name: DeviceActivityEvent]) throws -> Void
    var stop: ([DeviceActivityName]) -> Void
    var applyShields: (FamilyActivitySelection) -> Void
    var clearShields: () -> Void

    static var current = live

    static let live = ScreenTimeClient(
        now: Date.init,
        activities: { DeviceActivityCenter().activities },
        start: { try DeviceActivityCenter().startMonitoring($0, during: $1, events: $2) },
        stop: { DeviceActivityCenter().stopMonitoring($0) },
        applyShields: { selection in
            let store = ManagedSettingsStore(named: SharedSettings.storeName)
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
            store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        },
        clearShields: { ManagedSettingsStore(named: SharedSettings.storeName).clearAllSettings() }
    )
}

struct AccessWindow: Codable, Equatable {
    let id: UUID
    let challenge: PendingChallenge
    let expiration: Date

    var activity: DeviceActivityName { DeviceActivityName("outloud.access.\(id.uuidString)") }
}

enum AccessWindowManager {
    static func isAccessActivity(_ activity: DeviceActivityName) -> Bool {
        activity == SharedSettings.relockActivity || activity.rawValue.hasPrefix("outloud.access.")
    }

    static func expire(activity: DeviceActivityName? = nil) {
        if let activity, !isAccessActivity(activity) { return }
        let now = ScreenTimeClient.current.now()
        // Only expiration dates decide which shields to restore. A delayed
        // callback from a replaced monitor cannot revoke a newer window.
        let expired = SharedSettings.accessWindows.filter { $0.expiration <= now }
        SharedSettings.accessWindows.removeAll { $0.expiration <= now }
        if !expired.isEmpty { ScreenTimeClient.current.stop(expired.map(\.activity)) }
        if let legacyExpiration = SharedSettings.unlockExpiration, legacyExpiration <= now {
            SharedSettings.unlockExpiration = nil
        }
        ShieldManager.applySavedSelection()
    }

    static func clear() {
        let names = ScreenTimeClient.current.activities().filter(isAccessActivity)
        if !names.isEmpty { ScreenTimeClient.current.stop(names) }
        SharedSettings.accessWindows = []
        SharedSettings.unlockExpiration = nil
    }
}
