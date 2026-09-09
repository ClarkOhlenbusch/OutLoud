#if DEBUG && targetEnvironment(simulator)
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Simulator-only launch fixtures. Real views and model operations are used;
/// system permissions, tokens, audio and app launches are controlled here.
@MainActor
enum UITestScenario {
    static var scenario: String? { ProcessInfo.processInfo.environment["OUTLOUD_UI_TEST_SCENARIO"] }

    static func makeModel() -> AppModel? {
        guard let scenario else { return nil }
        let suite = "outloud.ui-tests.\(ProcessInfo.processInfo.environment["OUTLOUD_UI_TEST_ID"] ?? UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let defaults = UserDefaults(suiteName: suite)!
            SharedSettings.testStorage = (defaults, directory)
            let a = try token(1), b = try token(2)
            var selection = FamilyActivitySelection()
            selection.applicationTokens = [a, b]
            SharedSettings.selection = selection
            SharedSettings.acceptsSimilarAcknowledgements = true
            if scenario == "speech-interruption" || scenario == "speech-interruption-repeated" {
                SharedSettings.acceptsSimilarAcknowledgements = false
                SharedSettings.phrases = ["I am wasting my time on Instagram."]
            }
            SharedSettings.onboardingStep = OnboardingStep.apps.rawValue
            SharedSettings.onboardingCompleted = scenario != "onboarding"
            SharedSettings.protectionEnabled = true
            SharedSettings.returnMappings = []
            SharedSettings.pendingChallenge = nil
            var failures = scenario == "unlock-failure" ? 1 : 0
            var monitors: [DeviceActivityName: [DeviceActivityEvent.Name: DeviceActivityEvent]] = [:]
            ScreenTimeClient.current = ScreenTimeClient(
                now: Date.init, activities: { Array(monitors.keys) },
                start: { name, _, events in
                    if failures > 0 { failures -= 1; throw NSError(domain: "UITestMonitor", code: 1) }
                    monitors[name] = events
                }, stop: { names in names.forEach { monitors.removeValue(forKey: $0) } },
                applyShields: { _ in }, clearShields: {})
            ReturnLinkClient.open = { _, _ in false }
            NotificationPermissionClient.request = { true }
            if scenario == "automatic-return" {
                SharedSettings.returnMappings = [ApplicationReturnMapping(applicationToken: a, destination: .youTube)]
            }
            if scenario != "onboarding" && scenario != "mappings" {
                SharedSettings.pendingChallenge = .application(a)
            }
            return AppModel(demoMode: false)
        } catch {
            preconditionFailure("Invalid UI test fixture: \(error)")
        }
    }

    private static func token(_ value: UInt8) throws -> ApplicationToken {
        try JSONDecoder().decode(ApplicationToken.self, from: JSONEncoder().encode(["data": Data([value])]))
    }

    static func makeSpeechCapture() -> SpeechCapture? {
        guard scenario != nil else { return nil }
        return ScriptedSpeechCapture()
    }
}

@MainActor
private final class ScriptedSpeechCapture: SpeechCapture {
    private var attempts = 0
    func requestPermissions(_ completion: @escaping (Bool) -> Void) { completion(true) }
    func start(phrases: [String], receive: @escaping (SpeechCaptureEvent) -> Void) throws {
        attempts += 1
        let interrupt = (UITestScenario.scenario == "speech-interruption" && attempts == 1)
            || (UITestScenario.scenario == "speech-interruption-repeated" && attempts <= 2)
        let phrase = phrases.first ?? "I am making a bad choice"
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if interrupt {
                receive(.failure(NSError(domain: "kAFAssistantErrorDomain", code: 1107)))
            } else {
                receive(.transcript(phrase, isFinal: true))
            }
        }
    }
    func finish() {}
    func stop() {}
}
#endif
