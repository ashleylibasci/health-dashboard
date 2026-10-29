import Foundation
import HealthCore
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
    /// True with an eating-disorder history: widgets show the water total
    /// only, never "of" a goal or a progress bar. Optional so a snapshot
    /// saved before it existed still decodes.
    var waterGoalHidden: Bool? = nil
    var bottleML: Double
    /// Tonight's planned bedtime.
    var bedtime: Date?
    /// "In bed on time" streak, in nights.
    var bedtimeStreak: Int
    /// The drink "Log a latte" logs: her saved Latte, or her first saved drink.
    var quickDrink: QuickDrink? = nil
    /// Today's caffeine cutoff; nil when it falls before she's up (then
    /// `caffeineNote` says "One small drink early") and from older app builds.
    var caffeineCutoff: Date? = nil
    /// Today's combined pill (H-A1), for the Taken buttons on the Cycle
    /// widget and the Watch. nil when she isn't on the combined pill, and
    /// from older app builds.
    var pill: PillState? = nil

    struct QuickDrink: Codable, Equatable {
        var id: UUID
        var name: String
        var mg: Int
    }

    /// Where she is in the pack on one pill day, and whether that day's
    /// pill is taken.
    struct PillState: Codable, Equatable {
        /// Midnight of the pill day (`PillDay`: a dose up to 12 hours either
        /// side of the pill time counts for it).
        var day: Date
        var packDay: Int
        var activeDays: Int
        var packLength: Int
        /// Her pill time on this phone's clock.
        var time: Minutes
        var taken: Date?
        /// "Break week" or "Break days" (a 4-day break).
        var breakName: String = "Break week"

        var isPillDay: Bool { packDay <= activeDays }
        var isNewPack: Bool { packDay == 1 }
        /// Day 1, 2… of the break; nil on pill days.
        var breakDay: Int? { isPillDay ? nil : packDay - activeDays }
        /// Midnight of the next pack's first pill day.
        var newPackDay: Date? {
            Calendar.current.date(byAdding: .day, value: packLength - packDay + 1, to: day)
        }
        /// Today's pill time as a date.
        var pillTime: Date { day.addingTimeInterval(TimeInterval(time * 60)) }
    }

    /// The older Health Dashboard app's group (a free developer team can't
    /// register a new one). This app replaced it; its own key keeps it from
    /// reading the old app's leftover snapshot.
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
    var showsWaterGoal: Bool { waterGoalHidden != true && waterGoalML > 0 }

    /// Today's day-bound numbers, or nil once the app day they belong to has
    /// ended: yesterday's recovery, energy, cycle day and bedtime never show
    /// as today's.
    func recovery(at date: Date) -> Int? { isCurrent(at: date) ? recovery : nil }
    func energyLeft(at date: Date) -> Int? { isCurrent(at: date) ? energyLeft : nil }
    func cycleLine(at date: Date) -> String? { isCurrent(at: date) ? cycleLine : nil }
    func cycleNumber(at date: Date) -> Int? { isCurrent(at: date) ? cycleNumber : nil }
    func bedtime(at date: Date) -> Date? { isCurrent(at: date) ? bedtime : nil }
    func caffeineCutoff(at date: Date) -> Date? { isCurrent(at: date) ? caffeineCutoff : nil }

    /// The pill day `date` falls in. A later day than the saved one moves on
    /// through the pack, not yet taken; nil more than a week on (the pack
    /// may have changed since).
    func pill(at date: Date, calendar: Calendar = .current) -> PillState? {
        guard var p = pill else { return nil }
        let day = PillDay.day(for: date, pillTime: p.time, calendar: calendar)
        let ahead = calendar.dateComponents([.day], from: p.day, to: day).day ?? 0
        guard ahead > 0 else { return p }
        guard ahead <= 7 else { return nil }
        p.day = day
        p.packDay = (p.packDay - 1 + ahead) % p.packLength + 1
        p.taken = nil
        return p
    }
    /// Six hours or more since the app last read Apple Health.
    func isStale(at date: Date) -> Bool { date.timeIntervalSince(updated) >= 6 * 3600 || !isCurrent(at: date) }

    /// A believable example for widget galleries and previews.
    static let example = WidgetSnapshot(
        updated: .now, isSample: true, recovery: 69, recoveryLabel: "Take it steady", energyLeft: 58,
        cycleLine: "Pack day 18 \u{00B7} Active pill", cycleNumber: 18, cycleNumberLabel: "Pill",
        appDayStart: Calendar.current.startOfDay(for: .now), caffeineMg: 130, caffeineNote: "One small drink early",
        waterML: 1060, waterGoalML: 1893, bottleML: 710, bedtime: nil, bedtimeStreak: 4,
        quickDrink: QuickDrink(id: UUID(), name: "Latte", mg: 130),
        pill: PillState(day: Calendar.current.startOfDay(for: .now), packDay: 18, activeDays: 21, packLength: 28,
                        time: 21 * 60, taken: nil))
}

/// The Watch's smart alarm, for the Bedtime complication. Written to the App
/// Group by the Watch app whenever the alarm's state changes (the phone
/// never writes it).
struct WatchAlarmState: Codable, Equatable {
    /// On: rings by this time at the latest.
    var armedEnd: Date?
    /// On, but watchOS needs the app opened to turn it on (or to use a new window).
    var needsOpen: Bool

    private static let key = "next.watchAlarm.v1"

    static func load() -> WatchAlarmState? {
        guard let data = WidgetSnapshot.defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchAlarmState.self, from: data)
    }

    /// Saves it and redraws the Bedtime complication when it changed.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let old = WidgetSnapshot.defaults?.data(forKey: Self.key)
        guard old != data else { return }
        WidgetSnapshot.defaults?.set(data, forKey: Self.key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "WatchBedtime")
        #endif
    }
}
