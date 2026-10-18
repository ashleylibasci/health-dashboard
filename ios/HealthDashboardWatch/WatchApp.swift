import HealthKit
import SwiftUI
import WatchConnectivity
import WidgetKit

@main
struct HealthDashboardWatchApp: App {
    @State private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            // The Watch screens draw their own light and night looks, so keep the light palette here.
            WatchRootView().environment(store).environment(\.colorScheme, .light)
        }
    }
}

/// Holds the latest summary from the phone and logs drinks to Health on the Watch.
@MainActor
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    static let shared = WatchStore()

    var snapshot = WidgetSnapshot.load()
    var lastLogged: String?
    private let health = HKHealthStore()

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") { snapshot = .watchDemo }
        #endif
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.receive(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    /// Complication updates the phone sends in the background; saving reloads the watch-face complications.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.receive(userInfo) }
    }

    private func receive(_ context: [String: Any]) {
        guard let data = context["snapshot"] as? Data, let snap = WidgetSnapshot.decode(data) else { return }
        // Keep caffeine logged on the Watch today if the phone hasn't caught up yet.
        var merged = snap
        if snapshot.caffeineDay == snap.caffeineDay { merged.caffeineMg = max(snap.caffeineMg, snapshot.caffeineMg) }
        snapshot = merged
        merged.save()
    }

    // MARK: Logging

    func logLatte() async { await log(HKQuantityType(.dietaryCaffeine), .gramUnit(with: .milli), 130, "Latte saved") }
    func logWater() async { await log(HKQuantityType(.dietaryWater), .literUnit(with: .milli), 710, "Water saved") }
    func logDrink() async { await log(HKQuantityType(.numberOfAlcoholicBeverages), .count(), 1, "Drink saved") }

    private func log(_ type: HKQuantityType, _ unit: HKUnit, _ amount: Double, _ message: String) async {
        do {
            try await health.requestAuthorization(toShare: [type], read: [])
            try await health.save(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: amount), start: .now, end: .now))
            if type == HKQuantityType(.dietaryCaffeine) {
                let today = snapshotDay()
                snapshot.caffeineMg = (snapshot.caffeineDay == today ? snapshot.caffeineMg : 0) + amount
                snapshot.caffeineDay = today
                snapshot.save()
            }
            lastLogged = message
        } catch {
            lastLogged = "Couldn’t save to Health"
        }
    }

    private func snapshotDay() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}

#if DEBUG
extension WidgetSnapshot {
    /// Made-up numbers for checking Watch screens in the simulator: launch with `-demo`.
    static var watchDemo: WidgetSnapshot {
        var s = WidgetSnapshot()
        s.name = "Ashley"; s.recovery = 72; s.recoveryLabel = "Moderate"; s.headline = "Go easy today"
        s.cycleDay = 22; s.phase = "Luteal"; s.sleepMinutes = 430; s.bedBy = "12:15am"; s.energy = 58; s.streakNights = 6
        s.restingHr = 79; s.hrv = 38; s.hrUp = true; s.hrvDown = true
        s.typicalLength = 29; s.periodLength = 5; s.ovulationDay = 15; s.daysToPeriod = 7; s.tempDelta = 0.3
        s.caffeineAtBed = 17; s.examNote = "Midterm in 2 days. Tonight counts."; s.bedtimeMinutes = 375
        s.sick = ProcessInfo.processInfo.arguments.contains("-demoSick"); s.sickTonight = "Tonight: bed by 11:30, extra water."
        s.updated = .now
        return s
    }
}
#endif
