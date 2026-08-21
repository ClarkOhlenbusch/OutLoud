import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog

enum ShieldManager {
    private static var store: ManagedSettingsStore {
        ManagedSettingsStore(named: SharedSettings.storeName)
    }

    static func applySavedSelection() {
        guard SharedSettings.protectionEnabled else {
            OutLoudLog.screenTime.debug("Skipping saved selection because protection is disabled")
            clear()
            return
        }
        apply(SharedSettings.selection)
    }

    static func apply(_ selection: FamilyActivitySelection) {
        OutLoudLog.screenTime.info(
            "Applying shields; applications: \(selection.applicationTokens.count, privacy: .public), categories: \(selection.categoryTokens.count, privacy: .public), web domains: \(selection.webDomainTokens.count, privacy: .public)"
        )
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    static func release(_ challenge: PendingChallenge) {
        OutLoudLog.screenTime.info(
            "Releasing shield; challenge kind: \(challenge.logName, privacy: .public)"
        )
        var selection = SharedSettings.selection
        switch challenge {
        case .application(let token):
            selection.applicationTokens.remove(token)
        case .category(let token):
            selection.categoryTokens.remove(token)
        case .webDomain(let token):
            selection.webDomainTokens.remove(token)
        case .selection:
            clear()
            return
        case .practice:
            return
        }
        apply(selection)
    }

    static func rearmProtection() {
        guard SharedSettings.protectionEnabled else {
            OutLoudLog.shortcuts.debug("Re-arm skipped because protection is disabled")
            return
        }

        OutLoudLog.shortcuts.info("Re-arming protection")
        DeviceActivityCenter().stopMonitoring([SharedSettings.relockActivity])
        SharedSettings.unlockExpiration = nil
        applySavedSelection()
    }

    static func clear() {
        OutLoudLog.screenTime.info("Clearing all OutLoud managed settings")
        store.clearAllSettings()
    }
}
