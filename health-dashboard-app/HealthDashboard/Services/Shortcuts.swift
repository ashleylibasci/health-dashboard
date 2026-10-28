import AppIntents

/// Siri and Shortcuts phrases. No setup needed: they appear in the Shortcuts
/// app and Spotlight once the app is installed.
struct HealthNextShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogLatteIntent(),
                    phrases: ["Log a latte in \(.applicationName)",
                              "Log my latte in \(.applicationName)",
                              "Log a coffee in \(.applicationName)"],
                    shortTitle: "Log a latte",
                    systemImageName: "cup.and.saucer.fill")
    }
}
