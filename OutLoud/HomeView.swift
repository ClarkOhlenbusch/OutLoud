import FamilyControls
import ManagedSettings
import SwiftUI

private let outLoudAccent = Color(red: 0.96, green: 0.76, blue: 0.25)
private let accessWindowOptions: [(seconds: TimeInterval, title: String)] = [
    (15 * 60, "15 min"),
    (30 * 60, "30 min"),
    (60 * 60, "1 hour")
]

private func accessWindowTitle(for seconds: TimeInterval) -> String {
    accessWindowOptions.first { $0.seconds == seconds }?.title ?? "15 min"
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPicker = false
    @State private var showingDemoPicker = false
    @State private var showingPhraseEditor = false
    @State private var showingAskAgainSetup = false
    @State private var showingReturnSetup = false
    @State private var showingUsageReminderSetup = false

    var body: some View {
        NavigationStack {
            ZStack {
                OutLoudBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        wordmark
                        if model.isDemoMode { demoBanner }
                        protectionStatus
                        settings
                        practiceButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .familyActivityPicker(isPresented: $showingPicker, selection: $model.selection)
            .sheet(isPresented: $showingDemoPicker) {
                DemoAppPicker(selectedApps: $model.demoSelectedApps)
            }
            .sheet(isPresented: $showingPhraseEditor) {
                PhraseEditorView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showingAskAgainSetup) {
                AskAgainSetupView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showingReturnSetup) {
                AutoReturnSetupView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showingUsageReminderSetup) {
                UsageReminderSetupView()
                    .environmentObject(model)
            }
            .onChange(of: model.selection) { _, _ in model.saveSelection() }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Please try again.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            VoiceMark()
            Text("OutLoud")
                .font(.system(size: 24, weight: .black, design: .rounded))
            Spacer()
        }
    }

    private var protectionStatus: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 110, height: 110)
                Circle()
                    .stroke(statusColor.opacity(0.28), lineWidth: 1)
                    .frame(width: 110, height: 110)
                Image(systemName: model.protectionEnabled ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(spacing: 5) {
                Text(model.protectionEnabled ? "Protection is on" : "Protection is off")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(model.protectionEnabled ? "Turn off" : "Turn on") {
                model.setProtection(!model.protectionEnabled)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(model.protectionEnabled ? .white.opacity(0.72) : .black)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(
                model.protectionEnabled ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(outLoudAccent),
                in: Capsule()
            )
            .disabled(model.selectedItemCount == 0)
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
    }

    private var settings: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: "app.badge.checkmark",
                title: "Apps",
                value: selectionSummary
            ) {
                model.isDemoMode ? (showingDemoPicker = true) : (showingPicker = true)
            }

            Divider().overlay(.white.opacity(0.08)).padding(.leading, 56)

            SettingsRow(
                icon: "quote.bubble.fill",
                title: "Response",
                value: model.phraseSummary
            ) {
                showingPhraseEditor = true
            }

            Divider().overlay(.white.opacity(0.08)).padding(.leading, 56)

            SettingsRow(
                icon: "arrowshape.turn.up.right.fill",
                title: "Auto-return",
                value: returnSetupSummary
            ) {
                showingReturnSetup = true
            }

            Divider().overlay(.white.opacity(0.08)).padding(.leading, 56)

            SettingsRow(
                icon: "timer",
                title: "Ask again",
                value: askAgainSummary
            ) {
                showingAskAgainSetup = true
            }

            Divider().overlay(.white.opacity(0.08)).padding(.leading, 56)

            SettingsRow(
                icon: "bell.badge.fill",
                title: "Usage reminders",
                value: usageReminderSummary
            ) {
                showingUsageReminderSetup = true
            }
        }
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var practiceButton: some View {
        Button {
            model.beginPractice()
        } label: {
            Label("Practice the pause", systemImage: "mic.fill")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(outLoudAccent)
        .padding(.vertical, 8)
    }

    private var demoBanner: some View {
        Text("Simulator preview")
            .font(.caption.weight(.semibold))
            .foregroundStyle(outLoudAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(outLoudAccent.opacity(0.1), in: Capsule())
    }

    private var statusColor: Color {
        model.protectionEnabled ? outLoudAccent : .white.opacity(0.45)
    }

    private var statusDetail: String {
        guard model.selectedItemCount > 0 else { return "Choose at least one app" }
        return "\(model.selectedItemCount) app\(model.selectedItemCount == 1 ? "" : "s") will pause before opening"
    }

    private var selectionSummary: String {
        let count = model.selectedItemCount
        return count == 0 ? "Choose apps" : "\(count) selected"
    }

    private var returnSetupSummary: String {
        let total = model.selection.applicationTokens.count
        guard total > 0 else { return "Choose individual apps" }
        return model.mappedApplicationCount == total
            ? "Ready"
            : "\(model.mappedApplicationCount) of \(total)"
    }

    private var askAgainSummary: String {
        switch model.askAgainMode {
        case .everyVisit: "Every visit"
        case .afterTime: "After \(accessWindowTitle(for: model.gracePeriod))"
        }
    }

    private var usageReminderSummary: String {
        model.usageRemindersEnabled ? model.usageReminderInterval.summary : "Off"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPicker = false
    @State private var showingDemoPicker = false
    @State private var showingRearmSetup = false
    @State private var showingReturnSetup = false
    @State private var viewedRearmSetup = false
    @State private var onboardingReminderInterval: UsageReminderInterval = .fiveMinutes
    @State private var isEnablingUsageReminders = false
    @FocusState private var phraseIsFocused: Bool

    private var step: OnboardingStep { model.onboardingStep }

    var body: some View {
        ZStack {
            OutLoudBackground()

            VStack(spacing: 0) {
                if step != .welcome { progressHeader }
                currentPage
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $model.selection)
        .sheet(isPresented: $showingDemoPicker) {
            DemoAppPicker(selectedApps: $model.demoSelectedApps)
        }
        .sheet(isPresented: $showingRearmSetup, onDismiss: {
            viewedRearmSetup = true
        }) {
            RearmAutomationSetupView()
        }
        .sheet(isPresented: $showingReturnSetup) {
            AutoReturnSetupView(requiresCompleteMapping: true) {
                move(to: .phrase)
            }
            .environmentObject(model)
        }
        .onChange(of: model.selection) { _, _ in model.saveSelection() }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Please try again.")
        }
        .onAppear {
            onboardingReminderInterval = model.usageReminderInterval
        }
        .preferredColorScheme(.dark)
    }

    private var progressHeader: some View {
        HStack(spacing: 12) {
            Button {
                phraseIsFocused = false
                withAnimation(.easeInOut(duration: 0.25)) {
                    model.moveOnboarding(to: step.previous)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 6) {
                ForEach(1...OnboardingStep.progressCount, id: \.self) { item in
                    Capsule()
                        .fill(item <= step.rawValue ? outLoudAccent : .white.opacity(0.12))
                        .frame(height: 4)
                }
            }

            Color.clear.frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var currentPage: some View {
        switch step {
        case .welcome: welcomePage
        case .screenTime: permissionPage
        case .apps: appsPage
        case .phrase: phrasePage
        case .everyVisit: everyVisitPage
        case .usageReminders: usageRemindersPage
        case .ready: readyPage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            VoiceMark(size: 1.8)
                .padding(.bottom, 22)

            Text("OutLoud")
                .font(.system(size: 48, weight: .black, design: .rounded))
            Text("Turn autopilot into a choice.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            Spacer()

            primaryButton("Get started") {
                move(to: .screenTime)
            }
        }
    }

    private var permissionPage: some View {
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "Allow Screen Time",
            message: "This lets OutLoud pause only the apps you choose."
        ) {
            if model.isAuthorized {
                statusPill("Access allowed", icon: "checkmark")
            }
        } action: {
            primaryButton(model.isAuthorized ? "Continue" : "Allow access") {
                if model.isAuthorized {
                    move(to: .apps)
                } else {
                    Task {
                        await model.requestAuthorization()
                        if model.isAuthorized { move(to: .apps) }
                    }
                }
            }
        }
    }

    private var appsPage: some View {
        OnboardingPage(
            icon: "app.badge.checkmark",
            title: "Choose your apps",
            message: "Pick apps individually so OutLoud can return to the right one."
        ) {
            VStack(spacing: 12) {
                Button {
                    model.isDemoMode ? (showingDemoPicker = true) : (showingPicker = true)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: model.selectedItemCount == 0 ? "plus" : "checkmark")
                        Text(model.selectedItemCount == 0 ? "Choose apps" : "\(model.selectedItemCount) selected")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                if model.hasUnsupportedReturnSelection && !model.isDemoMode {
                    Label("Choose apps—not categories or websites.", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
        } action: {
            primaryButton("Continue") {
                if model.isDemoMode || !model.needsReturnSetup {
                    move(to: .phrase)
                } else {
                    showingReturnSetup = true
                }
            }
            .disabled(model.selectedItemCount == 0 || model.hasUnsupportedReturnSelection)
            .opacity(
                model.selectedItemCount == 0 || model.hasUnsupportedReturnSelection ? 0.35 : 1
            )
        }
    }

    private var phrasePage: some View {
        OnboardingPage(
            icon: "quote.bubble.fill",
            title: "What will you say?",
            message: model.acceptsSimilarAcknowledgements
                ? "Acknowledge it’s a bad choice."
                : "Say one of your phrases."
        ) {
            VStack(spacing: 14) {
                AcknowledgementModePicker(selection: acknowledgementMode)

                if !model.acceptsSimilarAcknowledgements {
                    TextEditor(text: $model.phrase)
                        .focused($phraseIsFocused)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120, maxHeight: 190)
                        .padding(14)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.acceptsSimilarAcknowledgements)
        } action: {
            primaryButton("Practice") {
                phraseIsFocused = false
                model.savePhrase()
                model.beginPractice()
            }
        }
    }

    private var acknowledgementMode: Binding<Bool> {
        Binding(
            get: { model.acceptsSimilarAcknowledgements },
            set: {
                phraseIsFocused = !$0
                model.setAcceptsSimilarAcknowledgements($0)
            }
        )
    }

    private var everyVisitPage: some View {
        OnboardingPage(
            icon: "timer",
            title: "When should we ask again?",
            message: "Choose whether leaving the app ends your access or a timer keeps it unlocked."
        ) {
            VStack(spacing: 12) {
                AskAgainOption(
                    icon: "arrow.clockwise",
                    title: "Every visit",
                    detail: "Ask again after you leave the app.",
                    selected: model.askAgainMode == .everyVisit
                ) {
                    model.setAskAgainMode(.everyVisit)
                }

                AskAgainOption(
                    icon: "timer",
                    title: "Use a timer",
                    detail: "Keep access open across visits.",
                    selected: model.askAgainMode == .afterTime
                ) {
                    model.setAskAgainMode(.afterTime)
                }

                if model.askAgainMode == .afterTime {
                    AccessWindowPicker(selection: Binding(
                        get: { model.gracePeriod },
                        set: { model.setGracePeriod($0) }
                    ))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if viewedRearmSetup {
                    statusPill("Automation steps viewed", icon: "checkmark")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.askAgainMode)
        } action: {
            VStack(spacing: 10) {
                primaryButton(onboardingTimingButtonTitle) {
                    if model.askAgainMode == .afterTime || viewedRearmSetup {
                        move(to: .usageReminders)
                    } else {
                        showingRearmSetup = true
                    }
                }

                if model.askAgainMode == .everyVisit {
                    Button(viewedRearmSetup ? "View steps again" : "Set up later") {
                        if viewedRearmSetup {
                            showingRearmSetup = true
                        } else {
                            move(to: .usageReminders)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(height: 40)
                }
            }
        }
    }

    private var onboardingTimingButtonTitle: String {
        if model.askAgainMode == .afterTime || viewedRearmSetup { return "Continue" }
        return "Set up every visit"
    }

    private var usageRemindersPage: some View {
        OnboardingPage(
            icon: "bell.badge.fill",
            title: "Interrupt the scroll",
            message: "Get a bold reminder while you’re using any app you selected—even when Protection is off."
        ) {
            VStack(spacing: 18) {
                UsageReminderIntervalPicker(selection: onboardingReminderInterval) { interval in
                    onboardingReminderInterval = interval
                }

                UsageReminderPreview(
                    elapsedMinutes: onboardingReminderInterval.rawValue,
                    appName: "TikTok",
                    compact: true
                )

                Label(
                    "Time counts only while each app is open and continues across visits.",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        } action: {
            VStack(spacing: 8) {
                primaryButton(isEnablingUsageReminders ? "Turning on…" : "Turn on reminders") {
                    Task { await enableOnboardingUsageReminders() }
                }
                .disabled(isEnablingUsageReminders)
                .opacity(isEnablingUsageReminders ? 0.65 : 1)

                Button("Not now") {
                    model.turnOffUsageReminders()
                    move(to: .ready)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(height: 40)
                .disabled(isEnablingUsageReminders)
            }
        }
    }

    @MainActor
    private func enableOnboardingUsageReminders() async {
        isEnablingUsageReminders = true
        defer { isEnablingUsageReminders = false }

        await model.selectUsageReminderInterval(onboardingReminderInterval)
        if model.usageRemindersEnabled,
           model.usageReminderInterval == onboardingReminderInterval {
            move(to: .ready)
        }
    }

    private var readyPage: some View {
        OnboardingPage(
            icon: "checkmark",
            title: "You’re ready",
            message: model.usageRemindersEnabled
                ? "Your reminders are on. Add Protection for an extra pause before selected apps open."
                : "OutLoud will pause before your selected apps open."
        ) {
            EmptyView()
        } action: {
            VStack(spacing: 8) {
                primaryButton("Turn on protection") {
                    model.finishOnboarding()
                }

                if model.usageRemindersEnabled {
                    Button("Use reminders only") {
                        model.finishOnboarding(enableProtection: false)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(height: 40)
                }
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle(color: outLoudAccent))
    }

    private func statusPill(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(outLoudAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(outLoudAccent.opacity(0.1), in: Capsule())
    }

    private func move(to nextStep: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.25)) {
            model.moveOnboarding(to: nextStep)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct OnboardingPage<Content: View, Action: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(outLoudAccent)
                .frame(width: 104, height: 104)
                .background(outLoudAccent.opacity(0.1), in: Circle())
                .padding(.bottom, 24)

            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 12)

            content()
                .padding(.top, 26)

            Spacer()

            action()
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(outLoudAccent)
                    .frame(width: 30)

                Text(title)
                    .font(.body.weight(.semibold))

                Spacer(minLength: 12)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PhraseEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var phraseIsFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                OutLoudBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(model.acceptsSimilarAcknowledgements
                            ? "Acknowledge it’s a bad choice."
                            : "Say one of your phrases.")
                            .font(.title2.bold())

                        AcknowledgementModePicker(selection: acknowledgementMode)

                        if !model.acceptsSimilarAcknowledgements {
                            TextEditor(text: $model.phrase)
                                .focused($phraseIsFocused)
                                .font(.title3.weight(.semibold))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 130, maxHeight: 220)
                                .padding(16)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Spacer()
                    }
                    .padding(20)
                    .animation(.easeInOut(duration: 0.2), value: model.acceptsSimilarAcknowledgements)
                }
            }
            .navigationTitle("Response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.savePhrase()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var acknowledgementMode: Binding<Bool> {
        Binding(
            get: { model.acceptsSimilarAcknowledgements },
            set: {
                phraseIsFocused = !$0
                model.setAcceptsSimilarAcknowledgements($0)
            }
        )
    }
}

private struct AcknowledgementModePicker: View {
    @Binding var selection: Bool

    var body: some View {
        HStack(spacing: 12) {
            modeCard(
                value: true,
                title: "Own words",
                icon: "waveform"
            )

            modeCard(
                value: false,
                title: "Specific phrases",
                icon: "quote.bubble.fill"
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func modeCard(value: Bool, title: String, icon: String) -> some View {
        let isSelected = selection == value

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = value
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.66))
                    .frame(width: 46, height: 46)
                    .background(
                        isSelected ? AnyShapeStyle(outLoudAccent) : AnyShapeStyle(.white.opacity(0.07)),
                        in: Circle()
                    )

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.64))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity, minHeight: 124)
            .background(
                isSelected ? outLoudAccent.opacity(0.1) : .white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? outLoudAccent.opacity(0.7) : .white.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(outLoudAccent)
                        .padding(10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AutoReturnSetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var requiresCompleteMapping = false
    var onComplete: (() -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                OutLoudBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Match each protected app once. After you say a phrase, OutLoud will send you straight back.")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        if model.protectedApplicationTokens.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 0) {
                                ForEach(model.protectedApplicationTokens, id: \.self) { token in
                                    returnMappingRow(for: token)

                                    if token != model.protectedApplicationTokens.last {
                                        Divider().overlay(.white.opacity(0.08))
                                    }
                                }
                            }
                            .background(
                                .white.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                        }

                        if model.hasUnsupportedReturnSelection {
                            Label(
                                "Categories and websites cannot identify the originating app. Choose apps individually for automatic return.",
                                systemImage: "info.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Auto-return")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        onComplete?()
                    }
                    .disabled(requiresCompleteMapping && model.needsReturnSetup)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(outLoudAccent)
            Text("Choose individual apps first")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
    }

    private func returnMappingRow(for token: ApplicationToken) -> some View {
        HStack(spacing: 12) {
            Label(token)
                .font(.body.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 12)

            Menu {
                ForEach(ReturnDestination.allCases) { destination in
                    Button {
                        model.setReturnDestination(destination, for: token)
                    } label: {
                        Label(destination.displayName, systemImage: destination.systemImageName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(model.returnDestination(for: token)?.displayName ?? "Choose")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    model.returnDestination(for: token) == nil ? outLoudAccent : .white.opacity(0.78)
                )
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.07), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 66)
    }
}

private struct AskAgainOption: View {
    let icon: String
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? outLoudAccent : .white.opacity(0.62))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 10)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? outLoudAccent : .white.opacity(0.22))
            }
            .foregroundStyle(.white)
            .padding(15)
            .background(
                selected ? outLoudAccent.opacity(0.1) : .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? outLoudAccent.opacity(0.5) : .white.opacity(0.07), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AccessWindowPicker: View {
    @Binding var selection: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep apps unlocked for")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            Picker("Keep apps unlocked for", selection: $selection) {
                ForEach(accessWindowOptions, id: \.seconds) { option in
                    Text(option.title).tag(option.seconds)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.top, 4)
    }
}

private struct UsageReminderSetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                OutLoudBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Interrupt the scroll")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("Choose how often OutLoud should interrupt you in any app selected under Apps. Reminders work whether protection is on or off.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        if model.usageRemindersEnabled {
                            Label(
                                "Always on · \(model.usageReminderInterval.summary)",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(outLoudAccent)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(outLoudAccent.opacity(0.1), in: Capsule())
                        }

                        VStack(alignment: .leading, spacing: 11) {
                            Text("Notify me every")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))

                            UsageReminderIntervalPicker(
                                selection: model.usageRemindersEnabled
                                    ? model.usageReminderInterval
                                    : nil
                            ) { interval in
                                Task { await model.selectUsageReminderInterval(interval) }
                            }
                        }

                        UsageReminderPreview(
                            elapsedMinutes: model.usageReminderInterval.rawValue,
                            appName: "TikTok"
                        )

                        Label(
                            "Time counts only while each selected app is frontmost, continues across visits, and resets daily. Notification delivery can be affected by Focus and system settings.",
                            systemImage: "info.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        if model.usageRemindersEnabled {
                            Button("Turn off usage reminders") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    model.turnOffUsageReminders()
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.38))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Usage reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Notifications unavailable", isPresented: errorBinding) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Allow notifications for OutLoud in Settings.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct UsageReminderPreview: View {
    let elapsedMinutes: Int
    let appName: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact {
                Text("PREVIEW")
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(outLoudAccent)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: compact ? 17 : 20, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: compact ? 36 : 40, height: compact ? 36 : 40)
                    .background(outLoudAccent, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 5) {
                    Text(UsageReminderNotification.title(
                        elapsedMinutes: elapsedMinutes,
                        appName: appName
                    ))
                    .font(.system(
                        size: compact ? 15 : 17,
                        weight: .black,
                        design: .rounded
                    ))
                    .fixedSize(horizontal: false, vertical: true)

                    if !compact {
                        Text(UsageReminderNotification.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(compact ? 14 : 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(outLoudAccent.opacity(0.34), lineWidth: 1)
        }
    }
}

private struct UsageReminderIntervalPicker: View {
    let selection: UsageReminderInterval?
    let select: (UsageReminderInterval) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(UsageReminderInterval.allCases) { interval in
                intervalButton(interval)
            }
        }
    }

    private func intervalButton(_ interval: UsageReminderInterval) -> some View {
        let isSelected = selection == interval

        return Button {
            select(interval)
        } label: {
            VStack(spacing: 3) {
                Text("\(interval.rawValue)")
                    .font(.subheadline.weight(.bold))
                Text(interval.rawValue == 1 ? "minute" : "minutes")
                    .font(.caption2.weight(.medium))
                    .opacity(0.72)
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected ? AnyShapeStyle(outLoudAccent) : AnyShapeStyle(.white.opacity(0.07)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? outLoudAccent : .white.opacity(0.08),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AskAgainSetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingRearmSetup = false

    var body: some View {
        NavigationStack {
            ZStack {
                OutLoudBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("When should OutLoud ask again?")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("This applies after you complete a phrase and unlock an app.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 12) {
                            AskAgainOption(
                                icon: "arrow.clockwise",
                                title: "Every visit",
                                detail: "Lock again when you leave the app.",
                                selected: model.askAgainMode == .everyVisit
                            ) {
                                model.setAskAgainMode(.everyVisit)
                            }

                            AskAgainOption(
                                icon: "timer",
                                title: "Use a timer",
                                detail: "Keep access open across app visits.",
                                selected: model.askAgainMode == .afterTime
                            ) {
                                model.setAskAgainMode(.afterTime)
                            }
                        }

                        if model.askAgainMode == .afterTime {
                            VStack(alignment: .leading, spacing: 14) {
                                AccessWindowPicker(selection: Binding(
                                    get: { model.gracePeriod },
                                    set: { model.setGracePeriod($0) }
                                ))

                                Label(
                                    "Your protected apps stay unlocked until the timer ends, even if you leave and come back.",
                                    systemImage: "info.circle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Every visit uses a personal automation in Shortcuts to lock protected apps again when you leave them.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Button {
                                    showingRearmSetup = true
                                } label: {
                                    Label("Set up Shortcuts automation", systemImage: "arrow.up.forward.app.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PrimaryButtonStyle(color: outLoudAccent))
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                    .animation(.easeInOut(duration: 0.2), value: model.askAgainMode)
                }
            }
            .navigationTitle("Ask again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingRearmSetup) {
                RearmAutomationSetupView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct RearmAutomationSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                OutLoudBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("In Shortcuts")
                            .font(.system(size: 30, weight: .bold, design: .rounded))

                        VStack(alignment: .leading, spacing: 18) {
                            setupStep(1, "Tap Automation in the bottom tab bar.")
                            setupStep(2, "Tap New Automation—or + if you already have one.")
                            setupStep(3, "Scroll down and tap App.")
                            setupStep(4, "Choose the same apps you protect in OutLoud.")
                            setupStep(5, "Select Is Closed and Run Immediately, then tap Next.")
                            setupStep(6, "Choose Re-arm Protection. If needed, tap New Blank Automation and search for it.")
                        }

                        Button {
                            guard let url = URL(string: "shortcuts://") else { return }
                            openURL(url)
                        } label: {
                            Label("Open Shortcuts", systemImage: "arrow.up.forward.app.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(color: outLoudAccent))
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Every visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(outLoudAccent, in: Circle())

            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
    }
}

private struct VoiceMark: View {
    var size: CGFloat = 1

    var body: some View {
        HStack(spacing: 4 * size) {
            ForEach(Array([14.0, 24.0, 34.0, 24.0, 14.0].enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(outLoudAccent)
                    .frame(width: 5 * size, height: height * size)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OutLoudBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.08, green: 0.07, blue: 0.11), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct DemoAppPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedApps: Set<String>

    private let apps = [
        ("Instagram", "camera.fill", Color.pink),
        ("TikTok", "music.note", Color.cyan),
        ("YouTube", "play.rectangle.fill", Color.red),
        ("Reddit", "bubble.left.and.bubble.right.fill", Color.orange),
        ("X", "textformat", Color.white)
    ]

    var body: some View {
        NavigationStack {
            List(apps, id: \.0) { app in
                Button {
                    if selectedApps.contains(app.0) {
                        selectedApps.remove(app.0)
                    } else {
                        selectedApps.insert(app.0)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: app.1)
                            .foregroundStyle(app.2)
                            .frame(width: 28)
                        Text(app.0)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: selectedApps.contains(app.0) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedApps.contains(app.0) ? .yellow : .secondary)
                    }
                }
            }
            .navigationTitle("Choose apps")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(color.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 15))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
