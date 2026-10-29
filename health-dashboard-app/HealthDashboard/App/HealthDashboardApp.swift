import SwiftUI
import HealthCore

@main
struct HealthDashboardApp: App {
    @StateObject private var store: DataStore
    @StateObject private var model: AppModel
    /// "dark" (default), "light" or "system".
    @AppStorage("appearance") private var appearance = "dark"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = DataStore()
        let model = AppModel(store: store)
        _store = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: model)
        DemoMode.applySetup(store: store, model: model)
        // Apple Health wakes the app with new data (also when it's closed).
        BackgroundHealth.shared.start(model)
        // Pill doses logged in Apple Health cancel that pill's reminders.
        PillHealth.startWatching(model)
        // Lattes from Siri or the widget: straight into the log when the
        // intent runs in this process, otherwise on the next activation.
        PendingDrinks.onAdded = { model.importPendingDrinks() }
        // Water, pills and stress tapped on a widget, the same way.
        PendingLogs.onAdded = { model.importPendingLogs() }
        // Wired here rather than in a view, so Watch messages that arrive when
        // iOS wakes the app in the background are still handled.
        WatchSync.shared.onMessage = { model.handle($0) }
        WatchSync.shared.onSnapshotRequest = { model.answerSnapshotRequest() }
        // A push before the session is active is dropped; send once it is.
        WatchSync.shared.onActivated = { model.pushToWatch() }
        WatchSync.shared.activate()
        // Sick alerts and nudges show as banners while the app is open too.
        NotificationPresenter.install()
        // "Taken" on a pill reminder, even with the app closed.
        NotificationPresenter.shared.onPillTaken = { at in MainActor.assumeIsolated { model.markPillTaken(at: at) } }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.data.onboarded {
                    RootTabView()
                        .motionTransition(.commit)
                } else {
                    OnboardingFlow()
                        .motionTransition(.commit)
                }
            }
            .environmentObject(store)
            .environmentObject(model)
            .environment(\.hidesEffortTargets, store.data.conditions.contains("Eating-disorder history"))
            .preferredColorScheme(appearance == "light" ? .light : appearance == "system" ? nil : .dark)
            .onChange(of: scenePhase, initial: true) { _, phase in
                // Every time the app comes forward: today's numbers, then the Watch.
                guard phase == .active else { return }
                Task { await model.becameActive() }
            }
        }
    }
}

/// Four tabs, each a navigation stack whose root has its own `TabHeader`
/// (so the system bar is hidden there). A link to another tab's main
/// screen switches tabs through `openTab` rather than pushing a copy.
struct RootTabView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var tab: AppTab = DemoMode.open == nil ? .today : .body
    /// `-demoOpen` (Debug): the screen pushed on Body at launch.
    @State private var demoOpen = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView().toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label("Today", systemImage: "house") }
                .tag(AppTab.today)
            NavigationStack { SleepView().toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label("Sleep", systemImage: "moon") }
                .tag(AppTab.sleep)
            NavigationStack {
                BodyView().toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(isPresented: $demoOpen) {
                        if DemoMode.open == "cycleSettings" { CycleSettingsView() } else { CycleView() }
                    }
                    .task {
                        guard DemoMode.open != nil, !demoOpen else { return }
                        try? await Task.sleep(for: .milliseconds(500))
                        demoOpen = true
                    }
            }
                .tabItem { Label("Body", systemImage: "heart") }
                .tag(AppTab.body)
            NavigationStack { LogView().toolbar(.hidden, for: .navigationBar) }
                .tabItem { Label("Log", systemImage: "plus") }
                .tag(AppTab.log)
        }
        .environment(\.openTab) { tab = $0 }
        // The app's chrome colour, not system blue.
        .tint(Accent.indigo.ink(scheme))
    }
}
