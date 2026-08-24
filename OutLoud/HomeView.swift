import FamilyControls
import ManagedSettings
import SwiftUI

private let outLoudAccent = Color(red: 0.96, green: 0.76, blue: 0.25)

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPicker = false
    @State private var showingDemoPicker = false
    @State private var showingPhraseEditor = false
    @State private var showingRearmSetup = false
    @State private var showingReturnSetup = false

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
            .sheet(isPresented: $showingRearmSetup) {
                RearmAutomationSetupView()
            }
            .sheet(isPresented: $showingReturnSetup) {
                AutoReturnSetupView()
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
                title: "Phrase",
                value: model.phrase
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
                icon: "arrow.clockwise",
                title: "Every visit",
                value: "Shortcuts setup"
            ) {
                showingRearmSetup = true
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
            title: "Choose your phrase",
            message: "Say it once now so your first real pause feels familiar."
        ) {
            TextField("Your phrase", text: $model.phrase, axis: .vertical)
                .focused($phraseIsFocused)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2...4)
                .padding(18)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        } action: {
            primaryButton("Practice this phrase") {
                phraseIsFocused = false
                model.savePhrase()
                model.beginPractice()
            }
        }
    }

    private var everyVisitPage: some View {
        OnboardingPage(
            icon: "arrow.clockwise",
            title: "Make it work every visit",
            message: "One Shortcuts automation re-arms OutLoud when you leave a protected app."
        ) {
            if viewedRearmSetup {
                statusPill("Instructions viewed", icon: "checkmark")
            }
        } action: {
            VStack(spacing: 10) {
                primaryButton(viewedRearmSetup ? "Continue" : "Show setup steps") {
                    if viewedRearmSetup {
                        move(to: .ready)
                    } else {
                        showingRearmSetup = true
                    }
                }

                Button(viewedRearmSetup ? "View steps again" : "Set up later") {
                    if viewedRearmSetup {
                        showingRearmSetup = true
                    } else {
                        move(to: .ready)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(height: 40)
            }
        }
    }

    private var readyPage: some View {
        OnboardingPage(
            icon: "checkmark",
            title: "You’re ready",
            message: "OutLoud will pause before your selected apps open."
        ) {
            EmptyView()
        } action: {
            primaryButton("Turn on protection") {
                model.finishOnboarding()
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

    private let suggestions = [
        "I am choosing to spend my time here",
        "This can wait",
        "I am making a bad choice"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                OutLoudBackground()

                VStack(alignment: .leading, spacing: 20) {
                    Text("What should you say before continuing?")
                        .font(.title2.bold())

                    TextField("Your phrase", text: $model.phrase, axis: .vertical)
                        .focused($phraseIsFocused)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2...4)
                        .padding(16)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                model.phrase = suggestion
                            } label: {
                                HStack {
                                    Text(suggestion)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if model.phrase == suggestion {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(outLoudAccent)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.76))

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Your phrase")
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
        .onAppear { phraseIsFocused = true }
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
                        Text("Match each protected app once. After you say your phrase, OutLoud will send you straight back.")
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
