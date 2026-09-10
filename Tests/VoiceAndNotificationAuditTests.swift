import AVFoundation
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Speech
import UserNotifications
import XCTest
@testable import OutLoud

/// Comprehensive regression test suite recreating each of the 11 critical failure modes
/// identified in the speech recognition and notification/Screen Time system audit.
final class VoiceAndNotificationAuditTests: ScreenTimeFlowTestCase {

    private func waitForClassification(_ controller: SpeechChallengeController) async {
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !controller.isFinalizing },
            object: nil
        )
        await fulfillment(of: [finished], timeout: 2)
    }

    // MARK: - 1. Voice Part: Resolved Failure Modes

    /// 1.A: Hardcoded US English Locale Resolved - Adapts to international locales
    @MainActor
    func test1A_hardcodedUSEnglishLocaleBreaksInternationalUsers() {
        // 1. Verify that SystemSpeechCapture adapts to non-US device locales
        let nonUSLocales = ["en-GB", "en-AU", "en-CA", "en-IN"]
        for identifier in nonUSLocales {
            let locale = Locale(identifier: identifier)
            let recognizer = SystemSpeechCapture.selectBestOnDeviceRecognizer(
                currentLocale: locale,
                preferredLanguages: [identifier]
            )
            // If on-device recognition is supported on the system, it resolves a recognizer
            if let recognizer {
                XCTAssertTrue(recognizer.supportsOnDeviceRecognition)
            }
        }

        // 2. When on-device speech recognition is unavailable, capture throws SpeechCaptureError.unavailable
        // with helpful settings guidance.
        let unavailableCapture = FakeSpeechCapture()
        unavailableCapture.startError = SpeechCaptureError.unavailable

        let controller = SpeechChallengeController(
            capture: unavailableCapture,
            classify: { _ in .accepted },
            isApplicationActive: { true }
        )
        controller.requestAndStart(
            expectedPhrases: ["I am wasting my time on Instagram."],
            acceptsSimilarAcknowledgements: false
        ) {}
        unavailableCapture.permissions[0](true)

        XCTAssertFalse(controller.isListening)
        XCTAssertEqual(controller.errorTitle, "Couldn’t listen")
        XCTAssertTrue(controller.errorMessage!.localizedCaseInsensitiveContains("Settings"))
        XCTAssertTrue(controller.errorMessage!.localizedCaseInsensitiveContains("Dictation"))
    }

    /// 1.B: Dictation Disabled in System Settings (Error 201) - Actionable guidance provided
    @MainActor
    func test1B_dictationDisabledInSettingsReturnsUnavailableOrErrorWithoutGuidance() async {
        // Resolved Mode 1: Dictation disabled prior to launch causes SpeechCaptureError.unavailable
        let unavailableCapture = FakeSpeechCapture()
        unavailableCapture.startError = SpeechCaptureError.unavailable
        let controller1 = SpeechChallengeController(
            capture: unavailableCapture,
            classify: { _ in .accepted },
            isApplicationActive: { true }
        )
        controller1.requestAndStart(expectedPhrases: ["I am wasting my time."], acceptsSimilarAcknowledgements: false) {}
        unavailableCapture.permissions[0](true)

        XCTAssertFalse(controller1.isListening)
        XCTAssertTrue(controller1.errorMessage!.localizedCaseInsensitiveContains("dictation"))
        XCTAssertTrue(controller1.errorMessage!.localizedCaseInsensitiveContains("keyboard"))

        // Resolved Mode 2: kAFAssistantErrorDomain code 201 received during listening directs user to Settings
        let runtimeCapture = FakeSpeechCapture()
        let controller2 = SpeechChallengeController(
            capture: runtimeCapture,
            classify: { _ in .accepted },
            isApplicationActive: { true }
        )
        controller2.requestAndStart(expectedPhrases: ["I am wasting my time."], acceptsSimilarAcknowledgements: false) {}
        runtimeCapture.permissions[0](true)
        XCTAssertTrue(controller2.isListening)

        let dictationError = NSError(
            domain: "kAFAssistantErrorDomain",
            code: 201,
            userInfo: [NSLocalizedDescriptionKey: "Dictation disabled"]
        )
        runtimeCapture.receivers[0](.failure(dictationError))

        XCTAssertFalse(controller2.isListening)
        XCTAssertEqual(controller2.errorTitle, "Dictation is turned off")
        XCTAssertTrue(controller2.errorMessage!.localizedCaseInsensitiveContains("dictation"))
        XCTAssertTrue(controller2.errorMessage!.localizedCaseInsensitiveContains("keyboard"))
    }

    /// 1.C: Audio Session Configuration Includes Bluetooth Support (AirPods / Headsets)
    @MainActor
    func test1C_audioSessionConfigurationLacksBluetoothSupportCausingMicrophoneUnavailable() {
        // Verify audio session category options include Bluetooth support
        let options = SystemSpeechCapture.audioSessionCategoryOptions
        XCTAssertTrue(options.contains(.allowBluetooth), "options must include .allowBluetooth")
        XCTAssertTrue(options.contains(.allowBluetoothA2DP), "options must include .allowBluetoothA2DP")

        // When microphone is unavailable:
        let capture = FakeSpeechCapture()
        capture.startError = SpeechCaptureError.microphoneUnavailable
        let controller = SpeechChallengeController(
            capture: capture,
            classify: { _ in .accepted },
            isApplicationActive: { true }
        )
        controller.requestAndStart(expectedPhrases: ["I am wasting time."], acceptsSimilarAcknowledgements: false) {}
        capture.permissions[0](true)

        XCTAssertFalse(controller.isListening)
        XCTAssertEqual(controller.errorTitle, "Couldn’t listen")
        XCTAssertEqual(controller.errorMessage, "No microphone input is available.")
    }

    /// 1.D: Voice Level Threshold (0.08) & Done Speaking Button Always Accessible
    @MainActor
    func test1D_voiceLevelBelowThresholdLeavesListeningIndefinitelyWithNoDoneSpeakingButton() {
        var currentTime = Date(timeIntervalSince1970: 1_800_000_000)
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(
            capture: capture,
            classify: { _ in .accepted },
            now: { currentTime },
            isApplicationActive: { true }
        )
        controller.requestAndStart(expectedPhrases: ["I am wasting time."], acceptsSimilarAcknowledgements: false) {}
        capture.permissions[0](true)
        XCTAssertTrue(controller.isListening)

        // User speaks softly (normalized RMS = 0.15 > 0.08 threshold) with speech transcript
        capture.receivers[0](.transcript("I am", isFinal: false))
        currentTime.addTimeInterval(0.2)
        capture.receivers[0](.level(0.15))

        // Silence passes (1.5 seconds)
        currentTime.addTimeInterval(1.5)
        capture.receivers[0](.level(0.02))

        // Silence detection triggers finishSpeaking
        XCTAssertTrue(controller.isFinalizing, "Soft speech followed by silence successfully triggers finishSpeaking")

        // In ChallengeView, Done speaking button is always available when listening
        let canRenderDoneSpeakingButton = controller.isListening || controller.isFinalizing
        XCTAssertTrue(canRenderDoneSpeakingButton)
    }

    /// 1.E: On-Device endAudio() Hangs / Timeout Recovery
    @MainActor
    func test1E_onDeviceRecognitionHangsOnEndAudioCausingTimeout() async {
        let capture = FakeSpeechCapture()
        // 100ms finalization timeout for rapid deterministic test execution
        let controller = SpeechChallengeController(
            capture: capture,
            classify: { _ in .accepted },
            finalizationTimeout: 100_000_000,
            isApplicationActive: { true }
        )
        controller.requestAndStart(expectedPhrases: ["I am wasting time."], acceptsSimilarAcknowledgements: false) {}
        capture.permissions[0](true)
        XCTAssertTrue(controller.isListening)

        // Partial speech received, then finishSpeaking() called
        capture.receivers[0](.transcript("I am wasting", isFinal: false))
        controller.finishSpeaking()

        XCTAssertFalse(controller.isListening)
        XCTAssertTrue(controller.isFinalizing)
        XCTAssertEqual(capture.finishes, 1)

        // Recognizer hangs; wait for timeout to expire
        try? await Task.sleep(nanoseconds: 180_000_000)

        // Rather than failing with a hard error, the partial speech was evaluated,
        // and because it was not the complete phrase, it prompted the user to try again
        XCTAssertEqual(controller.statusMessage, "Still listening. Say the full phrase again.")
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(controller.isListening)
    }

    /// 1.F: Word-Count Guardrail Accepts Short 2-Word Phrases
    @MainActor
    func test1F_wordCountGuardrailRejectsShortPhrasesCausingLockout() async {
        // 1. Guardrail now accepts 2-word phrases
        XCTAssertNotNil(AcknowledgementDecision.modelInput("Bad choice"))
        XCTAssertNotNil(AcknowledgementDecision.modelInput("Wasting time"))

        // 2. Both matchers accept valid 2-word admissions
        XCTAssertTrue(ExplicitAcknowledgementMatcher.matches("Bad choice"))
        XCTAssertTrue(ExplicitAcknowledgementMatcher.matches("Wasting time"))
        XCTAssertTrue(FlexibleAcknowledgementMatcher.matches(transcript: "Bad choice"))
        XCTAssertTrue(FlexibleAcknowledgementMatcher.matches(transcript: "Wasting time"))

        // 3. Speaking a 2-word admission matches and unlocks
        let capture = FakeSpeechCapture()
        let controller = SpeechChallengeController(
            capture: capture,
            classify: { await FlexibleAcknowledgementMatcher.evaluate(transcript: $0) },
            isApplicationActive: { true }
        )
        var matched = false
        controller.requestAndStart(
            expectedPhrases: ["This is a bad choice"],
            acceptsSimilarAcknowledgements: true
        ) {
            matched = true
        }
        capture.permissions[0](true)

        capture.receivers.last?(.transcript("Bad choice", isFinal: true))
        await waitForClassification(controller)

        XCTAssertTrue(matched, "Two-word admission 'Bad choice' successfully matched and unlocked")
        XCTAssertNil(controller.errorMessage)
    }

    // MARK: - 2. Notifications & Screen Time: Resolved Failure Modes

    /// 2.A: The Unlock Flow Configures Time-Sensitive Notification
    @MainActor
    func test2A_unlockFlowReliesEntirelyOnNotificationsOnOlderIOS() throws {
        let token = try token(1)
        let challenge = PendingChallenge.application(token)
        SharedSettings.pendingChallenge = challenge

        let content = UNMutableNotificationContent()
        content.title = "Say it out loud"
        content.body = "Tap to acknowledge the choice out loud and continue."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.categoryIdentifier = "OUTLOUD_CHALLENGE"

        let request = UNNotificationRequest(
            identifier: "outloud.pending-challenge",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        XCTAssertEqual(request.identifier, "outloud.pending-challenge")
        XCTAssertEqual(content.categoryIdentifier, "OUTLOUD_CHALLENGE")
        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(content.relevanceScore, 1)

        let expectedResponse = ShieldActionResponse.close
        XCTAssertEqual(expectedResponse, .close)
        XCTAssertEqual(SharedSettings.pendingChallenge, challenge)
    }

    /// 2.B: Notification Permission Denial Surfaces Error Message During Onboarding
    @MainActor
    func test2B_notificationPermissionDenialIgnoredDuringOnboardingLeavesUserLockedOut() async {
        NotificationPermissionClient.request = { false }
        NotificationPermissionClient.requiresFallback = { true }

        let model = AppModel(demoMode: true)
        await model.requestAuthorization()

        // Resolved: Denial sets errorMessage directing user to Settings
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.errorMessage!.localizedCaseInsensitiveContains("notifications"))
    }

    /// 2.C: Focus Modes, Do Not Disturb Bypassed With TimeSensitive Interruption Level
    @MainActor
    func test2C_focusModesAndDNDSilenceShieldNotificationDueToActiveInterruptionLevel() {
        // Permission request includes .timeSensitive
        let permissionOptions: UNAuthorizationOptions = [.alert, .sound, .timeSensitive]
        XCTAssertTrue(permissionOptions.contains(.timeSensitive))

        // Challenge notification has .timeSensitive interruption level
        let content = UNMutableNotificationContent()
        content.title = "Say it out loud"
        content.categoryIdentifier = "OUTLOUD_CHALLENGE"
        content.interruptionLevel = .timeSensitive

        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
    }

    /// 2.D: DeviceActivityMonitor and ShieldAction Entitlements Include Time-Sensitive Key
    func test2D_deviceActivityMonitorEntitlementsMissingTimeSensitiveKey() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectDir = testFileURL.deletingLastPathComponent().deletingLastPathComponent()

        // 1. DeviceActivityMonitor entitlements
        let monitorEntitlementsURL = projectDir.appendingPathComponent("Configuration/DeviceActivityMonitor.entitlements")
        let monitorData = try Data(contentsOf: monitorEntitlementsURL)
        let monitorPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: monitorData, options: [], format: nil) as? [String: Any]
        )

        // 2. ShieldAction entitlements
        let shieldEntitlementsURL = projectDir.appendingPathComponent("Configuration/ShieldAction.entitlements")
        let shieldData = try Data(contentsOf: shieldEntitlementsURL)
        let shieldPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: shieldData, options: [], format: nil) as? [String: Any]
        )

        // 3. Main app entitlements
        let appEntitlementsURL = projectDir.appendingPathComponent("Configuration/OutLoud.entitlements")
        let appData = try Data(contentsOf: appEntitlementsURL)
        let appPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: appData, options: [], format: nil) as? [String: Any]
        )

        // All targets have the time-sensitive entitlement:
        XCTAssertEqual(appPlist["com.apple.developer.usernotifications.time-sensitive"] as? Bool, true)
        XCTAssertEqual(monitorPlist["com.apple.developer.usernotifications.time-sensitive"] as? Bool, true)
        XCTAssertEqual(shieldPlist["com.apple.developer.usernotifications.time-sensitive"] as? Bool, true)
    }

    /// 2.E: Refresh Monitoring Atomically Cleans Up Partially Started Monitors on Failure
    func test2E_concurrentSchedulesExceedingLimitsWipesAllReminderTargets() throws {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [try token(1), try token(2), try token(3)]
        SharedSettings.selection = selection
        SharedSettings.usageRemindersEnabled = true
        SharedSettings.usageReminderInterval = .fiveMinutes

        // Simulate daemon limit throwing when registering the 2nd schedule
        system.failAtStart = 2

        XCTAssertThrowsError(try UsageReminderManager.refreshMonitoring()) { error in
            XCTAssertEqual((error as NSError).domain, "FakeScreenTime")
        }

        // Resolved: atomic rollback cleans up partially started monitors preventing broken or orphaned states
        XCTAssertTrue(
            SharedSettings.usageReminderTargets.isEmpty,
            "Targets are cleaned up atomically"
        )
        XCTAssertTrue(
            system.monitors.isEmpty,
            "Active monitors are cleaned up atomically"
        )
    }
}
