import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var now = Date.now
    /// "glow" (the default, always dark like the Watch) or "light" (the original look, dark at night if she wants).
    @AppStorage(Appearance.key) private var appearance = "glow"
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// The warm dark night version from 8pm to 6am (test builds can force it with `-night`).
    private var isNight: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-night") { return true }
        #endif
        guard model.profile?.prefs.nightMode ?? true else { return false }
        let hour = Calendar.current.component(.hour, from: now)
        return hour >= 20 || hour < 6
    }

    /// While the app is open, look at the calendar again every 30 minutes.
    private let calendarTimer = Timer.publish(every: 30 * 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.healthState == .unavailable {
                UnavailableView()
            } else if let screen = debugScreen {
                NavigationStack { screen }
            } else if model.profile == nil {
                OnboardingView()
            } else {
                tabs
            }
        }
        // A new identity when the look changes, so every color is worked out again.
        .id(appearance)
        .tint(.mainText)
        .preferredColorScheme(appearance == "glow" || isNight ? .dark : .light)
        .onReceive(minuteTimer) { now = $0 }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.refreshHealth()
                await model.refreshCalendar()
                await model.scheduleNotifications()
                model.publishWidgetSnapshot()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            Task { await model.phoneUnlocked() }
        }
        .onReceive(calendarTimer) { _ in Task { await model.refreshCalendar(force: true) } }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// Test builds only: `-screen cycle` (etc.) opens one screen directly, for checking layouts.
    private var debugScreen: AnyView? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "cycle": return AnyView(CycleView())
        case "phases": return AnyView(PhasesView())
        case "stress": return AnyView(StressView())
        case "energy": return AnyView(EnergyView())
        case "fitness": return AnyView(FitnessView())
        case "drinks": return AnyView(DrinksView())
        case "calories": return AnyView(CaloriesView())
        case "recovery": return AnyView(RecoveryView())
        case "sick": return AnyView(SickView())
        case "streaks": return AnyView(StreaksView())
        case "stages": return AnyView(SleepStagesView())
        case "sleep": return AnyView(SleepView())
        case "log": return AnyView(LogView())
        case "birthcontrol": return AnyView(BirthControlView(method: .combinedPill))
        case "conditions": return AnyView(ConditionsView())
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private var tabs: some View {
        TabView {
            Tab("Today", systemImage: "house.fill") { NavigationStack { TodayView(showSettings: $showSettings) } }
            Tab("Sleep", systemImage: "moon.fill") { NavigationStack { SleepView() } }
            Tab("Body", systemImage: "heart.fill") { NavigationStack { BodyView() } }
            Tab("Log", systemImage: "plus") { NavigationStack { LogView() } }
        }
    }
}

struct UnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash").font(.largeTitle).foregroundStyle(Color.muted)
            Text("Apple Health isn’t available on this device.").font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ground)
    }
}
