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
        // Lattes from Siri or the widget: straight into the log when the
        // intent runs in this process, otherwise on the next activation.
        PendingDrinks.onAdded = { model.importPendingDrinks() }
        // Wired here rather than in a view, so Watch messages that arrive when
        // iOS wakes the app in the background are still handled.
        WatchSync.shared.onMessage = { model.handle($0) }
        WatchSync.shared.onSnapshotRequest = { model.answerSnapshotRequest() }
        // A push before the session is active is dropped; send once it is.
        WatchSync.shared.onActivated = { model.pushToWatch() }
        WatchSync.shared.activate()
        // Sick alerts and nudges show as banners while the app is open too.
        NotificationPresenter.install()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.data.onboarded {
                    RootTabView()
                } else {
                    OnboardingFlow()
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

struct RootTabView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "house") }
            NavigationStack { SleepView() }
                .tabItem { Label("Sleep", systemImage: "moon") }
            NavigationStack { BodyView() }
                .tabItem { Label("Body", systemImage: "heart") }
            NavigationStack { LogView() }
                .tabItem { Label("Log", systemImage: "plus") }
        }
        // The app's chrome colour, not system blue.
        .tint(Accent.indigo.ink(scheme))
    }
}
