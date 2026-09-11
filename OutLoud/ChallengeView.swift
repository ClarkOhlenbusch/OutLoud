import SwiftUI
import UIKit

enum ActiveChallengeInput: String {
    case speak
    case type
}

struct ChallengeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speech = SpeechChallengeController()
    @State private var completed = false
    @State private var started = false
    @State private var usesSpecificPhrases = false
    @State private var returnDestination: ReturnDestination?
    @State private var isReturning = false
    @State private var returnTask: Task<Void, Never>?
    @State private var ambientBreathing = false
    @State private var unlockShockwave = false
    @State private var rejectionShakeAttempts: CGFloat = 0

    @State private var activeInput: ActiveChallengeInput = .speak
    @State private var typedText = ""
    @State private var typedErrorMessage: String?
    @FocusState private var isTextFieldFocused: Bool

    private let typingRequirement = "This is a bad choice"
    private let accent = Color(red: 0.96, green: 0.76, blue: 0.25)

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.022, blue: 0.04).ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: activeInput == .type ? 14 : 24) {
                        if activeInput == .speak {
                            Spacer()
                        }

                        if model.challengeMode == .either && !completed {
                            Picker("Challenge mode", selection: Binding(
                                get: { activeInput },
                                set: { switchInputMode(to: $0) }
                            )) {
                                Text("Speak").tag(ActiveChallengeInput.speak)
                                Text("Type").tag(ActiveChallengeInput.type)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 220)
                            .accessibilityIdentifier("challenge-mode-switcher")
                        }

                        voiceOrb

                        VStack(spacing: activeInput == .type ? 6 : 14) {
                            Text(completionTitle)
                                .font(.system(size: activeInput == .type ? 16 : 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(completed ? .green : .white.opacity(0.7))

                            Text(challengePrompt)
                                .font(.system(size: activeInput == .type ? 20 : 24, weight: .semibold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("challenge-prompt")
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)

                            if activeInput == .speak {
                                if !completed && !speech.transcript.isEmpty {
                                    Text(speech.transcript)
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundStyle(accent.opacity(0.82))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .padding(.horizontal, 18)
                                        .transition(.opacity)
                                } else if !completed, let rejected = speech.lastRejectedTranscript {
                                    Text("Heard: “\(rejected)”")
                                        .font(.callout)
                                        .foregroundStyle(accent.opacity(0.82))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(3)
                                        .modifier(ShakeEffect(animatableData: rejectionShakeAttempts))
                                }

                                if !completed, let message = speech.statusMessage {
                                    Text(message)
                                        .font(.callout)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        if activeInput == .type && !completed {
                            VStack(spacing: 12) {
                                HStack {
                                    TextField("This is a bad choice", text: $typedText)
                                        .focused($isTextFieldFocused)
                                        .font(.system(size: 17, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white)
                                        .autocorrectionDisabled(false)
                                        .textInputAutocapitalization(.sentences)
                                        .submitLabel(.go)
                                        .onSubmit { submitTypedText() }
                                        .accessibilityIdentifier("challenge-text-field")

                                    if !typedText.isEmpty {
                                        Button {
                                            typedText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white.opacity(0.4))
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(
                                            typedErrorMessage != nil ? Color.red.opacity(0.7) : (isTextFieldFocused ? accent.opacity(0.7) : .white.opacity(0.12)),
                                            lineWidth: 1.5
                                        )
                                }
                                .modifier(ShakeEffect(animatableData: rejectionShakeAttempts))

                                if let error = typedErrorMessage {
                                    Text(error)
                                        .font(.callout)
                                        .foregroundStyle(.red)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.horizontal, 10)
                                }

                                Button {
                                    SensoryFeedbackClient.shared.buttonTap()
                                    submitTypedText()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "lock.open.fill")
                                        Text("Unlock")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PrimaryButtonStyle(color: accent))
                                .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("challenge-submit-button")
                            }
                            .padding(.horizontal, 10)
                        }

                        if !completed, acceptsSimilarAcknowledgements, activeInput == .speak,
                           speech.lastRejectedTranscript != nil {
                            Button("Say a specific phrase instead") {
                                SensoryFeedbackClient.shared.selection()
                                usesSpecificPhrases = true
                                startListening()
                            }
                            .buttonStyle(.bordered)
                            .tint(accent)
                        }

                        if activeInput == .speak, let error = model.challengeErrorMessage ?? speech.errorMessage, !completed {
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 24)

                            if error.localizedCaseInsensitiveContains("Settings") {
                                Button("Open Settings") {
                                    SensoryFeedbackClient.shared.buttonTap()
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(accent)
                            }

                            Button(model.challengeErrorMessage == nil ? "Restart listening" : "Try unlocking again") {
                                SensoryFeedbackClient.shared.buttonTap()
                                if model.challengeErrorMessage != nil {
                                    finishChallenge()
                                } else {
                                    startListening()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .foregroundStyle(.black)
                        } else if activeInput == .type, let error = model.challengeErrorMessage, !completed {
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 24)

                            Button("Try unlocking again") {
                                SensoryFeedbackClient.shared.buttonTap()
                                finishChallenge()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .foregroundStyle(.black)
                        }

                        if model.isDemoMode && !completed {
                            Button("Simulate a matching phrase") {
                                SensoryFeedbackClient.shared.buttonTap()
                                speech.stop()
                                isTextFieldFocused = false
                                finishChallenge()
                            }
                            .buttonStyle(.bordered)
                            .tint(accent)
                        }

                        if activeInput == .speak && speech.isListening && !completed {
                            Button("Done speaking") {
                                SensoryFeedbackClient.shared.buttonTap()
                                speech.finishSpeaking()
                            }
                            .buttonStyle(.bordered)
                            .tint(accent)
                        }

                        if model.challengeMode == .either && !completed {
                            Button {
                                switchInputMode(to: activeInput == .speak ? .type : .speak)
                            } label: {
                                Label(
                                    activeInput == .speak ? "Type instead" : "Speak instead",
                                    systemImage: activeInput == .speak ? "keyboard.fill" : "mic.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(accent)
                            .accessibilityIdentifier("challenge-switch-input-button")
                        }

                        if activeInput == .speak {
                            Spacer()
                        } else {
                            Spacer(minLength: 12)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, activeInput == .type ? 24 : 64)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, minHeight: activeInput == .type ? nil : geometry.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: closeChallenge) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.06), in: Circle())
                    }
                    .accessibilityLabel(completed ? "Close" : "Cancel pause")
                }
                Spacer()
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if completed {
                if isPractice {
                    Button(model.onboardingCompleted ? "Done" : "Continue setup") {
                        SensoryFeedbackClient.shared.selection()
                        if !model.onboardingCompleted {
                            model.moveOnboarding(to: .everyVisit)
                        }
                        model.dismissChallenge()
                    }
                    .font(.body.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity)
                    .background(accent, in: RoundedRectangle(cornerRadius: 15))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                } else {
                    returnControl
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            SensoryFeedbackClient.shared.prepare()
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                ambientBreathing = true
            }
            guard !started else { return }
            started = true
            activeInput = (model.challengeMode == .type) ? .type : .speak
            if activeInput == .speak {
                if model.challengeErrorMessage == nil { startListening() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isTextFieldFocused = true
                }
            }
        }
        .onDisappear {
            speech.stop()
            isTextFieldFocused = false
            returnTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && !completed && activeInput == .speak { speech.pauseForBackground() }
        }
        .onChange(of: speech.lastRejectedTranscript) { _, rejected in
            guard rejected != nil else { return }
            SensoryFeedbackClient.shared.phraseRejected()
            withAnimation(.easeInOut(duration: 0.35)) {
                rejectionShakeAttempts += 1
            }
        }
        .onChange(of: speech.audioLevel) { _, newLevel in
            if newLevel > 0.35 && speech.isListening {
                SensoryFeedbackClient.shared.voiceActivityTick(intensity: newLevel)
            }
        }
    }

    private func switchInputMode(to mode: ActiveChallengeInput) {
        guard activeInput != mode, !completed else { return }
        SensoryFeedbackClient.shared.selection()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeInput = mode
            typedErrorMessage = nil
        }
        if mode == .type {
            speech.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        } else {
            isTextFieldFocused = false
            startListening()
        }
    }

    private func startListening() {
        SensoryFeedbackClient.shared.prepare()
        SensoryFeedbackClient.shared.selection()
        SensoryFeedbackClient.shared.playMicStartSound()
        speech.requestAndStart(
            expectedPhrases: model.phrases,
            acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements
        ) {
            finishChallenge()
        }
    }

    private func submitTypedText() {
        let trimmed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        SensoryFeedbackClient.shared.selection()
        typedErrorMessage = nil

        // Interrogative Rejection: questions can never unlock
        if trimmed.contains("?") || trimmed.contains("？") {
            SensoryFeedbackClient.shared.phraseRejected()
            withAnimation(.easeInOut(duration: 0.35)) {
                rejectionShakeAttempts += 1
            }
            typedErrorMessage = "Questions are not acknowledgments. State it as a fact."
            return
        }

        if PhraseMatcher.matches(transcript: trimmed, expected: typingRequirement) {
            finishChallenge()
        } else {
            SensoryFeedbackClient.shared.phraseRejected()
            withAnimation(.easeInOut(duration: 0.35)) {
                rejectionShakeAttempts += 1
            }
            typedErrorMessage = "Type “\(typingRequirement)” to unlock."
        }
    }

    private var acceptsSimilarAcknowledgements: Bool {
        model.acceptsSimilarAcknowledgements && !usesSpecificPhrases
    }

    private var challengePrompt: String {
        if activeInput == .type {
            return "Type: “\(typingRequirement)”"
        }
        if acceptsSimilarAcknowledgements {
            return "In your own words, acknowledge this is a bad choice"
        }
        if model.phrases.count == 1 {
            return "“\(model.phrases[0])”"
        }
        let visiblePhrases = model.phrases.prefix(3).map { "“\($0)”" }
        let remainingCount = model.phrases.count - visiblePhrases.count
        let remainder = remainingCount > 0 ? "\n+ \(remainingCount) more" : ""
        return "Say any one:\n" + visiblePhrases.joined(separator: "\n") + remainder
    }

    private var isPractice: Bool {
        model.pendingChallenge == .practice
    }

    private var completionTitle: String {
        if completed { return isPractice ? "That’s it" : "Unlocked" }
        if model.challengeErrorMessage != nil { return "Couldn’t unlock" }
        if activeInput == .type {
            if typedErrorMessage != nil { return "Couldn’t match" }
            return "Type to unlock"
        }
        if speech.errorMessage != nil { return speech.errorTitle }
        if speech.isRecovering { return "Reconnecting" }
        if speech.isFinalizing { return "Checking phrase" }
        return speech.isListening ? "Listening" : "Getting ready"
    }

    private var voiceOrb: some View {
        let isType = activeInput == .type && !completed
        let orbSize: CGFloat = isType ? 76 : 178
        let outerSize: CGFloat = isType ? 108 : 250
        let middleSize: CGFloat = isType ? 92 : 218
        let color = completed ? Color.green : accent
        let level: CGFloat = (activeInput == .speak && speech.isListening) ? max(speech.audioLevel, 0.025) : 0
        let ambientPulse: CGFloat = (!completed && !isType && level <= 0.04)
            ? (ambientBreathing ? 1.04 : 0.97)
            : 1.0
        let baseScale: CGFloat = isType ? 1.0 : ((1.0 + (level * 0.7)) * ambientPulse)
        let middleScale: CGFloat = isType ? 1.0 : ((1.0 + (level * 0.42)) * ambientPulse)
        let innerScale: CGFloat = isType ? 1.0 : ((1.0 + (level * 0.4)) * ambientPulse)
        let glowOpacity: Double = isType ? 0.22 : Double(min(1.0, 0.28 + (level * 0.55)))
        let centerOpacity: Double = completed ? 0.28 : (isType ? 0.35 : Double(min(1.0, 0.4 + (level * 0.35))))
        let strokeOpacity: Double = isType ? 0.35 : Double(min(1.0, 0.22 + (level * 0.35)))
        let shadowRadius: CGFloat = isType ? 12.0 : (24.0 + (level * 42.0))
        let barWeights: [CGFloat] = [0.55, 0.82, 1.0, 0.82, 0.55]

        return ZStack {
            if completed {
                Circle()
                    .stroke(Color.green.opacity(unlockShockwave ? 0 : 0.65), lineWidth: unlockShockwave ? 1 : 4)
                    .frame(width: 178, height: 178)
                    .scaleEffect(unlockShockwave ? 1.75 : 1.0)
            }

            Circle()
                .fill(color.opacity(0.08))
                .frame(width: outerSize, height: outerSize)
                .scaleEffect(baseScale)
                .blur(radius: isType ? 4 : 8)

            Circle()
                .stroke(color.opacity(strokeOpacity), lineWidth: isType ? 1.5 : 2)
                .frame(width: middleSize, height: middleSize)
                .scaleEffect(middleScale)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(centerOpacity),
                            color.opacity(0.82),
                            color.opacity(0.2)
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: isType ? 45 : 115
                    )
                )
                .frame(width: orbSize, height: orbSize)
                .scaleEffect(innerScale)
                .shadow(color: color.opacity(glowOpacity), radius: shadowRadius)

            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(unlockShockwave ? 1.0 : 0.8)
            } else if activeInput == .type {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(Array(barWeights.enumerated()), id: \.offset) { _, weight in
                        Capsule()
                            .fill(.white.opacity(0.88))
                            .frame(width: 8, height: 18 + (72 * level * weight))
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isType)
        .animation(.linear(duration: 0.08), value: speech.audioLevel)
        .animation(.easeOut(duration: 0.25), value: completed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(completed ? "Phrase accepted" : (activeInput == .type ? "Type acknowledgment" : "Voice level"))
    }

    private func finishChallenge() {
        let destination = model.returnDestinationForPendingChallenge()
        guard model.completeChallenge() else { return }
        isTextFieldFocused = false
        returnDestination = destination
        SensoryFeedbackClient.shared.phraseAccepted()
        SensoryFeedbackClient.shared.playUnlockSound()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            completed = true
        }
        withAnimation(.easeOut(duration: 0.65)) {
            unlockShockwave = true
        }

        guard !isPractice, let destination else { return }
        isReturning = true
        returnTask = Task {
            // Give Managed Settings a brief moment to remove the originating
            // app's shield before asking iOS to open it again.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await openReturnDestination(destination)
        }
    }

    private func closeChallenge() {
        SensoryFeedbackClient.shared.buttonTap()
        speech.stop()
        isTextFieldFocused = false
        returnTask?.cancel()
        isReturning = false

        if completed {
            model.dismissChallenge()
        } else {
            model.cancelChallenge()
        }
    }

    @ViewBuilder
    private var returnControl: some View {
        if let returnDestination {
            Button {
                SensoryFeedbackClient.shared.buttonTap()
                Task { await openReturnDestination(returnDestination) }
            } label: {
                HStack(spacing: 9) {
                    if isReturning {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "arrow.up.forward.app.fill")
                    }
                    Text(isReturning ? "Returning to \(returnDestination.displayName)…" : "Return to \(returnDestination.displayName)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(color: accent))
            .disabled(isReturning)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            VStack(spacing: 8) {
                Text("Swipe right along the bottom edge to go back.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Capsule()
                        .fill(.white.opacity(0.48))
                        .frame(width: 112, height: 5)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(.white.opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 2)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @MainActor
    private func openReturnDestination(_ destination: ReturnDestination) async {
        isReturning = true
        defer { isReturning = false }

        for url in destination.launchURLs {
            let options: [UIApplication.OpenExternalURLOptionsKey: Any]
            if url.scheme == "https" {
                options = [.universalLinksOnly: true]
            } else {
                options = [:]
            }

            if await ReturnLinkClient.open(url, options) {
                OutLoudLog.challenge.info(
                    "Opened automatic return destination: \(destination.displayName, privacy: .public)"
                )
                return
            }
        }

        OutLoudLog.challenge.error(
            "Could not open automatic return destination: \(destination.displayName, privacy: .public)"
        )
    }
}

@MainActor
enum ReturnLinkClient {
    static var open: (URL, [UIApplication.OpenExternalURLOptionsKey: Any]) async -> Bool = {
        await UIApplication.shared.open($0, options: $1)
    }
}

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amount * sin(animatableData * .pi * shakesPerUnit),
                y: 0
            )
        )
    }
}
