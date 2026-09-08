import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog

enum ShieldManager {
    static func applySavedSelection() {
        guard SharedSettings.protectionEnabled else {
            OutLoudLog.screenTime.debug("Skipping saved selection because protection is disabled")
            clear()
            return
        }
        var selection = SharedSettings.selection
        for window in SharedSettings.accessWindows where window.expiration > ScreenTimeClient.current.now() {
            switch window.challenge {
            case .application(let token): selection.applicationTokens.remove(token)
            case .category(let token): selection.categoryTokens.remove(token)
            case .webDomain(let token): selection.webDomainTokens.remove(token)
            case .selection:
                clear()
                return
            case .practice: break
            }
        }
        apply(selection)
    }

    static func apply(_ selection: FamilyActivitySelection) {
        OutLoudLog.screenTime.info(
            "Applying shields; applications: \(selection.applicationTokens.count, privacy: .public), categories: \(selection.categoryTokens.count, privacy: .public), web domains: \(selection.webDomainTokens.count, privacy: .public)"
        )
        ScreenTimeClient.current.applyShields(selection)
    }

    static func rearmProtection() {
        guard SharedSettings.protectionEnabled else {
            OutLoudLog.shortcuts.debug("Re-arm skipped because protection is disabled")
            return
        }
        guard SharedSettings.askAgainMode == .everyVisit else {
            OutLoudLog.shortcuts.debug("Re-arm skipped because the timed access window is selected")
            return
        }

        OutLoudLog.shortcuts.info("Re-arming protection")
        AccessWindowManager.clear()
        applySavedSelection()
    }

    static func clear() {
        OutLoudLog.screenTime.info("Clearing all OutLoud managed settings")
        ScreenTimeClient.current.clearShields()
    }
}
