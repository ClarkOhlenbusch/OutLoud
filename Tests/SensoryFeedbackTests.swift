import XCTest
@testable import OutLoud

final class SensoryFeedbackTests: ScreenTimeFlowTestCase {
    @MainActor
    func testSensoryDefaultsAndPersistence() {
        XCTAssertTrue(SharedSettings.hapticsEnabled)

        SharedSettings.hapticsEnabled = false
        XCTAssertFalse(SharedSettings.hapticsEnabled)

        SharedSettings.hapticsEnabled = true
        XCTAssertTrue(SharedSettings.hapticsEnabled)
    }

    @MainActor
    func testAppModelSynchronizesSensorySettings() {
        SharedSettings.hapticsEnabled = true

        let model = AppModel(demoMode: true)
        XCTAssertTrue(model.hapticsEnabled)

        model.setHapticsEnabled(false)
        XCTAssertFalse(model.hapticsEnabled)
        XCTAssertFalse(SharedSettings.hapticsEnabled)

        model.setHapticsEnabled(true)
        XCTAssertTrue(model.hapticsEnabled)
        XCTAssertTrue(SharedSettings.hapticsEnabled)
    }

    @MainActor
    func testSensoryFeedbackClientExecutesCleanlyWhenEnabledAndDisabled() {
        let client = SensoryFeedbackClient.shared

        // Test with haptics enabled
        SharedSettings.hapticsEnabled = true

        client.prepare()
        client.selection()
        client.buttonTap()
        client.lockToggle(isOn: true)
        client.lockToggle(isOn: false)
        client.voiceActivityTick(intensity: 0.8)
        client.voiceActivityTick(intensity: 0.2) // Within throttle window
        client.phraseAccepted()
        client.phraseRejected()
        client.previewUnlockFeedback()

        // Test with haptics disabled
        SharedSettings.hapticsEnabled = false

        client.prepare()
        client.selection()
        client.buttonTap()
        client.lockToggle(isOn: true)
        client.lockToggle(isOn: false)
        client.voiceActivityTick(intensity: 0.9)
        client.phraseAccepted()
        client.phraseRejected()
        client.previewUnlockFeedback()
    }
}
