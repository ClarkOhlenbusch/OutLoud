import AppIntents
import OSLog

struct RearmProtectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Re-arm Protection"
    static let description = IntentDescription(
        "Reapplies OutLoud protection after you leave a protected app when Every Visit is selected."
    )

#if compiler(>=6.3)
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }
#endif

    func perform() async throws -> some IntentResult {
        OutLoudLog.shortcuts.info("Re-arm shortcut invoked")
        ShieldManager.rearmProtection()
        return .result()
    }
}

struct OutLoudShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RearmProtectionIntent(),
            phrases: [
                "Re-arm \(.applicationName)",
                "Turn \(.applicationName) protection back on"
            ],
            shortTitle: "Re-arm Protection",
            systemImageName: "lock.shield.fill"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .yellow }
}
