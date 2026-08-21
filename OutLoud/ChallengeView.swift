import SwiftUI

struct ChallengeView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var speech = SpeechChallengeController()
    @State private var completed = false
    @State private var started = false

    private let accent = Color(red: 0.96, green: 0.76, blue: 0.25)

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.022, blue: 0.04).ignoresSafeArea()

            VStack(spacing: 42) {
                Spacer()

                voiceOrb

                VStack(spacing: 14) {
                    Text(completionTitle)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(completed ? .green : .white.opacity(0.7))

                    Text("“\(model.phrase)”")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)

                    if !completed && !speech.transcript.isEmpty {
                        Text(speech.transcript)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(accent.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 18)
                            .transition(.opacity)
                    }
                }

                if let error = speech.errorMessage, !completed {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button("Try again") { startListening() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .foregroundStyle(.black)
                }

                if model.isDemoMode && !completed {
                    Button("Simulate a matching phrase") {
                        speech.stop()
                        finishChallenge()
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                }

                Spacer()
            }
            .padding(24)

            if !completed {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            speech.stop()
                            model.cancelChallenge()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.06), in: Circle())
                        }
                        .accessibilityLabel("Cancel pause")
                    }
                    Spacer()
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if completed {
                if isPractice {
                    Button(model.onboardingCompleted ? "Done" : "Continue setup") {
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
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard !started else { return }
            started = true
            startListening()
        }
        .onDisappear { speech.stop() }
    }

    private func startListening() {
        speech.requestAndStart(expectedPhrase: model.phrase) {
            finishChallenge()
        }
    }

    private var isPractice: Bool {
        model.pendingChallenge == .practice
    }

    private var completionTitle: String {
        if completed { return isPractice ? "That’s it" : "Unlocked" }
        return speech.isListening ? "Listening" : "Getting ready"
    }

    private var voiceOrb: some View {
        let color = completed ? Color.green : accent
        let level = speech.isListening ? max(speech.audioLevel, 0.025) : 0

        return ZStack {
            Circle()
                .fill(color.opacity(0.08))
                .frame(width: 250, height: 250)
                .scaleEffect(1 + (level * 0.7))
                .blur(radius: 8)

            Circle()
                .stroke(color.opacity(0.22 + (level * 0.35)), lineWidth: 2)
                .frame(width: 218, height: 218)
                .scaleEffect(1 + (level * 0.42))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(completed ? 0.28 : 0.4 + (level * 0.35)),
                            color.opacity(0.82),
                            color.opacity(0.2)
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 115
                    )
                )
                .frame(width: 178, height: 178)
                .scaleEffect(1 + (level * 0.4))
                .shadow(color: color.opacity(0.28 + (level * 0.55)), radius: 24 + (level * 42))

            if completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(Array([0.55, 0.82, 1.0, 0.82, 0.55].enumerated()), id: \.offset) { _, weight in
                        Capsule()
                            .fill(.white.opacity(0.88))
                            .frame(width: 8, height: 18 + (72 * level * weight))
                    }
                }
            }
        }
        .animation(.linear(duration: 0.08), value: speech.audioLevel)
        .animation(.easeOut(duration: 0.25), value: completed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(completed ? "Phrase accepted" : "Voice level")
    }

    private func finishChallenge() {
        guard model.completeChallenge() else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            completed = true
        }
    }
}
