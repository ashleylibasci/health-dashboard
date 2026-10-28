import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The glanceable numbers the widgets and Watch complications show, written
/// by the app to the shared App Group after every refresh and every log.
/// Widgets can't read Apple Health or the app's own files, so this is all
/// they know; `updated` says how old it is.
struct WidgetSnapshot: Codable, Equatable {
    var updated: Date
    /// The app is still showing example data (fewer than 14 real nights, or
    /// the simulator): widgets say "Example".
    var isSample: Bool
    /// nil: no recovery reading yet today.
    var recovery: Int?
    var recoveryLabel: String
    /// "Energy left", 0–100.
    var energyLeft: Int?
    /// "Pack day 18 · Active pill", "Day 12 · Follicular"…; nil when she
    /// isn't tracking a cycle.
    var cycleLine: String?
    /// The big number for the cycle widget ("18"), and what it counts ("Pill", "Day").
    var cycleNumber: Int?
    var cycleNumberLabel: String?
    /// Start of the app day the caffeine and water totals belong to; after
    /// it rolls over the widgets show 0 rather than yesterday's totals.
    var appDayStart: Date
    var caffeineMg: Int
    /// "Cutoff 2pm", or "One small drink early" on the pill.
    var caffeineNote: String
    var waterML: Double
    var waterGoalML: Double
    var bottleML: Double
    /// Tonight's planned bedtime.
    var bedtime: Date?
    /// "In bed on time" streak, in nights.
    var bedtimeStreak: Int
    /// The drink "Log a latte" logs: her saved Latte, or her first saved drink.
    var quickDrink: QuickDrink? = nil

    struct QuickDrink: Codable, Equatable {
        var id: UUID
        var name: String
        var mg: Int
    }

    /// Shared with the older Health Dashboard app from `ios/` (a free
    /// developer team can't register a new group), so Health Next keeps
    /// its own key: the two apps' widgets never read each other's numbers.
    static let appGroup = "group.com.ashleylibasci.healthdashboard"
    private static let key = "next.widgetSnapshot.v1"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// The saved snapshot as sent to the Watch (which keeps its own copy for
    /// the watch-face complications).
    static var savedData: Data? { defaults?.data(forKey: key) }

    /// Watch side: the phone's snapshot arrived.
    static func receive(_ data: Data) {
        guard let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        s.save()
    }

    /// Saves it and asks every widget to redraw (only when something changed,
    /// to stay inside WidgetKit's reload budget).
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let old = Self.defaults?.data(forKey: Self.key)
        Self.defaults?.set(data, forKey: Self.key)
        #if canImport(WidgetKit)
        if old != data { WidgetCenter.shared.reloadAllTimelines() }
        #endif
    }

    /// Today's totals, or 0 once the app day they belong to has ended.
    func caffeineMg(at date: Date) -> Int { isCurrent(at: date) ? caffeineMg : 0 }
    func waterML(at date: Date) -> Double { isCurrent(at: date) ? waterML : 0 }
    func isCurrent(at date: Date) -> Bool { date.timeIntervalSince(appDayStart) < 24 * 3600 }

    /// A believable example for widget galleries and previews.
    static let example = WidgetSnapshot(
        updated: .now, isSample: true, recovery: 69, recoveryLabel: "Take it steady", energyLeft: 58,
        cycleLine: "Pack day 18 \u{00B7} Active pill", cycleNumber: 18, cycleNumberLabel: "Pill",
        appDayStart: Calendar.current.startOfDay(for: .now), caffeineMg: 130, caffeineNote: "One small drink early",
        waterML: 1060, waterGoalML: 1893, bottleML: 710, bedtime: nil, bedtimeStreak: 4,
        quickDrink: QuickDrink(id: UUID(), name: "Latte", mg: 130))
}
