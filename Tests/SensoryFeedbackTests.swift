import XCTest
@testable import OutLoud

final class SensoryFeedbackTests: ScreenTimeFlowTestCase {
    @MainActor
    func testSensoryDefaultsAndPersistence() {
        XCTAssertTrue(SharedSettings.hapticsEnabled)
        XCTAssertTrue(SharedSettings.soundEffectsEnabled)

        SharedSettings.hapticsEnabled = false
        SharedSettings.soundEffectsEnabled = false
        XCTAssertFalse(SharedSettings.hapticsEnabled)
        XCTAssertFalse(SharedSettings.soundEffectsEnabled)

        SharedSettings.hapticsEnabled = true
        SharedSettings.soundEffectsEnabled = true
        XCTAssertTrue(SharedSettings.hapticsEnabled)
        XCTAssertTrue(SharedSettings.soundEffectsEnabled)
    }

    @MainActor
    func testAppModelSynchronizesSensorySettings() {
        SharedSettings.hapticsEnabled = true
        SharedSettings.soundEffectsEnabled = true

        let model = AppModel(demoMode: true)
        XCTAssertTrue(model.hapticsEnabled)
        XCTAssertTrue(model.soundEffectsEnabled)

        model.setHapticsEnabled(false)
        XCTAssertFalse(model.hapticsEnabled)
        XCTAssertFalse(SharedSettings.hapticsEnabled)

        model.setSoundEffectsEnabled(false)
        XCTAssertFalse(model.soundEffectsEnabled)
        XCTAssertFalse(SharedSettings.soundEffectsEnabled)

        model.setHapticsEnabled(true)
        model.setSoundEffectsEnabled(true)
        XCTAssertTrue(model.hapticsEnabled)
        XCTAssertTrue(model.soundEffectsEnabled)
        XCTAssertTrue(SharedSettings.hapticsEnabled)
        XCTAssertTrue(SharedSettings.soundEffectsEnabled)
    }

    @MainActor
    func testSensoryFeedbackClientExecutesCleanlyWhenEnabledAndDisabled() {
        let client = SensoryFeedbackClient.shared

        // Test with haptics and sound enabled
        SharedSettings.hapticsEnabled = true
        SharedSettings.soundEffectsEnabled = true

        client.prepare()
        client.selection()
        client.buttonTap()
        client.lockToggle(isOn: true)
        client.lockToggle(isOn: false)
        client.voiceActivityTick(intensity: 0.8)
        client.voiceActivityTick(intensity: 0.2) // Within throttle window
        client.phraseAccepted()
        client.phraseRejected()
        client.playUnlockSound()
        client.playMicStartSound()
        client.previewUnlockFeedback()

        // Test with haptics and sound disabled
        SharedSettings.hapticsEnabled = false
        SharedSettings.soundEffectsEnabled = false

        client.prepare()
        client.selection()
        client.buttonTap()
        client.lockToggle(isOn: true)
        client.lockToggle(isOn: false)
        client.voiceActivityTick(intensity: 0.9)
        client.phraseAccepted()
        client.phraseRejected()
        client.playUnlockSound()
        client.playMicStartSound()
        client.previewUnlockFeedback()
    }
}
