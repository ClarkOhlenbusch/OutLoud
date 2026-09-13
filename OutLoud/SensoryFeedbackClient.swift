import UIKit

@MainActor
final class SensoryFeedbackClient {
    static let shared = SensoryFeedbackClient()

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)

    private var lastVoiceTick: Date = .distantPast
    private let minVoiceTickInterval: TimeInterval = 0.28

    init() {
        prepare()
    }

    func prepare() {
        guard SharedSettings.hapticsEnabled else { return }
        selectionFeedback.prepare()
        notificationFeedback.prepare()
        softImpact.prepare()
        lightImpact.prepare()
        rigidImpact.prepare()
    }

    func selection() {
        guard SharedSettings.hapticsEnabled else { return }
        selectionFeedback.selectionChanged()
    }

    func buttonTap() {
        guard SharedSettings.hapticsEnabled else { return }
        lightImpact.impactOccurred(intensity: 0.7)
    }

    func lockToggle(isOn: Bool) {
        guard SharedSettings.hapticsEnabled else { return }
        if isOn {
            rigidImpact.impactOccurred(intensity: 1.0)
        } else {
            mediumImpact.impactOccurred(intensity: 0.75)
        }
    }

    func voiceActivityTick(intensity: CGFloat = 0.6) {
        guard SharedSettings.hapticsEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastVoiceTick) >= minVoiceTickInterval else { return }
        lastVoiceTick = now
        softImpact.impactOccurred(intensity: max(0.35, min(1.0, intensity)))
    }

    func phraseAccepted() {
        guard SharedSettings.hapticsEnabled else { return }
        notificationFeedback.notificationOccurred(.success)
    }

    func phraseRejected() {
        guard SharedSettings.hapticsEnabled else { return }
        notificationFeedback.notificationOccurred(.warning)
    }

    func previewUnlockFeedback() {
        phraseAccepted()
    }
}
