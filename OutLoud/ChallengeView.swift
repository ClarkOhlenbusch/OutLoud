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
    @StateObject private var typed = TypedChallengeController()
    @State private var completed = false
    @State private var started = false
    @State private var usesSpecificPhrases = false
    @State private var returnDestination: ReturnDestination?
    @State private var isReturning = false
    @State private var returnFailed = false
    @State private var viewSessionID = UUID()
    @State private var returnTask: Task<Void, Never>?
    @State private var ambientBreathing = false
    @State private var unlockShockwave = false
    @State private var rejectionShakeAttempts: CGFloat = 0

    @State private var activeInput: ActiveChallengeInput = .speak
    @State private var typedText = ""
    @FocusState private var isTextFieldFocused: Bool

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
                            .contentShape(Circle())
                            .onTapGesture {
                                handleOrbTap()
                            }

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
                                    TextField(
                                        acceptsSimilarAcknowledgements
                                            ? "Type your acknowledgment…"
                                            : "Type the phrase…",
                                        text: $typedText
                                    )
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
                                            typed.errorMessage != nil ? Color.red.opacity(0.7) : (isTextFieldFocused ? accent.opacity(0.7) : .white.opacity(0.12)),
                                            lineWidth: 1.5
                                        )
                                }
                                .modifier(ShakeEffect(animatableData: rejectionShakeAttempts))

                                if let error = typed.errorMessage {
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
                                        if typed.isChecking {
                                            ProgressView()
                                                .tint(.black)
                                        } else {
                                            Image(systemName: "lock.open.fill")
                                        }
                                        Text(typed.isChecking ? "Checking…" : "Unlock")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PrimaryButtonStyle(color: accent))
                                .disabled(typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || typed.isChecking)
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
                        } else if !completed, acceptsSimilarAcknowledgements, activeInput == .type,
                                  typed.errorMessage != nil {
                            Button("Type a specific phrase instead") {
                                SensoryFeedbackClient.shared.selection()
                                usesSpecificPhrases = true
                                typed.cancel()
                            }
                            .buttonStyle(.bordered)
                            .tint(accent)
                        }
                        
                        if activeInput == .speak {
                            retryInstructionPill
                        }

                        if activeInput == .type, let error = model.challengeErrorMessage, !completed {
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

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    if let error = speakingErrorMessage {
                        topErrorBanner(error)
                    } else {
                        Spacer()
                    }

                    Button(action: closeChallenge) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.06), in: Circle())
                    }
                    .accessibilityLabel(completed ? "Close" : "Cancel pause")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
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
            viewSessionID = model.challengeSessionID
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
            typed.cancel()
            speech.stop()
            isTextFieldFocused = false
            returnTask?.cancel()
        }
        .onChange(of: typedText) { _, _ in typed.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                typed.cancel()
                returnTask?.cancel()
                if !completed && activeInput == .speak { speech.pauseForBackground() }
            }
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
        typed.cancel()
        SensoryFeedbackClient.shared.selection()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeInput = mode
            typed.cancel()
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
        speech.requestAndStart(
            expectedPhrases: model.phrases,
            acceptsSimilarAcknowledgements: acceptsSimilarAcknowledgements
        ) {
            finishChallenge()
        }
    }

    private func submitTypedText() {
        guard !completed, UIApplication.shared.applicationState == .active else { return }
        SensoryFeedbackClient.shared.selection()
        typed.submit(typedText, phrases: model.phrases,
                     acceptsSimilar: acceptsSimilarAcknowledgements) {
            guard activeInput == .type, UIApplication.shared.applicationState == .active else { return }
            finishChallenge()
        } onReject: {
            SensoryFeedbackClient.shared.phraseRejected()
            withAnimation(.easeInOut(duration: 0.35)) {
                rejectionShakeAttempts += 1
            }
        }
    }

    private var acceptsSimilarAcknowledgements: Bool {
        model.acceptsSimilarAcknowledgements && !usesSpecificPhrases
    }

    private var challengePrompt: String {
        let isText = activeInput == .type
        if acceptsSimilarAcknowledgements {
            return isText
                ? "In your own words, type an acknowledgment that this is a bad choice"
                : "In your own words, acknowledge this is a bad choice"
        }
        if model.phrases.count == 1 {
            return isText
                ? "Type: “\(model.phrases[0])”"
                : "“\(model.phrases[0])”"
        }
        let visiblePhrases = model.phrases.prefix(3).map { "“\($0)”" }
        let remainingCount = model.phrases.count - visiblePhrases.count
        let remainder = remainingCount > 0 ? "\n+ \(remainingCount) more" : ""
        let verb = isText ? "Type" : "Say"
        return "\(verb) any one:\n" + visiblePhrases.joined(separator: "\n") + remainder
    }

    private var isPractice: Bool {
        model.pendingChallenge == .practice
    }

    private var completionTitle: String {
        if completed { return isPractice ? "That’s it" : "Unlocked" }
        if model.challengeErrorMessage != nil { return "Couldn’t unlock" }
        if activeInput == .type {
            if typed.isChecking { return "Checking phrase" }
            if typed.errorMessage != nil { return "Couldn’t match" }
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
        .accessibilityAddTraits(activeInput == .speak ? [.isButton] : [])
        .accessibilityIdentifier(speech.isListening ? "Done speaking" : "voice-orb")
        .accessibilityLabel(completed ? "Phrase accepted" : (activeInput == .type ? "Type acknowledgment" : (speech.isListening ? "Done speaking" : "Voice level")))
    }

    private var speakingErrorMessage: String? {
        guard activeInput == .speak, !completed else { return nil }
        return model.challengeErrorMessage ?? speech.errorMessage
    }

    private var canTapToRetry: Bool {
        if model.challengeErrorMessage != nil && !completed {
            return true
        }
        return activeInput == .speak && !completed && !speech.isListening && !speech.isFinalizing && started
    }

    private var retryButtonIdentifier: String {
        model.challengeErrorMessage != nil ? "Try unlocking again" : "Restart listening"
    }

    private var retryInstructionTitle: String {
        if model.challengeErrorMessage != nil {
            return "Try unlocking again"
        }
        if speech.errorMessage != nil || speech.lastRejectedTranscript != nil {
            return "Tap orb to try again"
        }
        return "Tap orb to speak"
    }

    private func handleOrbTap() {
        guard activeInput == .speak, !completed else { return }
        SensoryFeedbackClient.shared.buttonTap()
        if speech.isListening {
            speech.finishSpeaking()
        } else {
            if model.challengeErrorMessage != nil {
                finishChallenge()
            } else {
                startListening()
            }
        }
    }

    @ViewBuilder
    private var retryInstructionPill: some View {
        if canTapToRetry {
            Button {
                handleOrbTap()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.bold())
                    Text(retryInstructionTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(retryButtonIdentifier)
            .accessibilityLabel(retryButtonIdentifier)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    private func topErrorBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16, weight: .bold))

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if message.localizedCaseInsensitiveContains("Settings") {
                Button("Settings") {
                    SensoryFeedbackClient.shared.buttonTap()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accent, in: Capsule())
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: message)
    }

    private func finishChallenge() {
        guard !completed, UIApplication.shared.applicationState == .active else { return }
        let destination = model.returnDestinationForPendingChallenge()
        guard model.completeChallenge(expectedSessionID: viewSessionID) else { return }
        typed.cancel()
        speech.stop()
        isTextFieldFocused = false
        returnDestination = destination
        SensoryFeedbackClient.shared.phraseAccepted()
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
        typed.cancel()
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
        VStack(spacing: 12) {
            if let returnDestination {
                Button {
                    SensoryFeedbackClient.shared.buttonTap()
                    returnTask?.cancel()
                    returnTask = Task { await openReturnDestination(returnDestination) }
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
            }
            if returnDestination == nil || returnFailed {
                VStack(spacing: 8) {
                    if returnFailed {
                        Text("Automatic return didn’t open the app. Switch back manually.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                    }
                    Text("Open the app from the App Switcher or Home Screen.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
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
    }

    @MainActor
    private func openReturnDestination(_ destination: ReturnDestination) async {
        isReturning = true
        returnFailed = false
        defer { isReturning = false }

        for url in destination.launchURLs {
            guard !Task.isCancelled else { return }
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

        guard !Task.isCancelled else { return }
        returnFailed = true
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
