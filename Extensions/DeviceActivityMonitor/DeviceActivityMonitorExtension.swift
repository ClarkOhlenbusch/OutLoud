import DeviceActivity
import OSLog

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == SharedSettings.relockActivity else {
            OutLoudLog.screenTime.debug("Ignoring unrelated Device Activity interval")
            return
        }
        OutLoudLog.screenTime.info("Access window ended; reapplying shields")
        SharedSettings.unlockExpiration = nil
        ShieldManager.applySavedSelection()
    }
}
