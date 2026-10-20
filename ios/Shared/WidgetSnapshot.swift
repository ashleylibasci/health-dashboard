import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The handful of numbers the widgets show. The app writes it to the shared App Group
/// container each time it reads Health; the widgets only read it.
struct WidgetSnapshot: Codable, Equatable {
    var name: String = ""
    var recovery: Int?
    var recoveryLabel: String = ""
    var headline: String = "Open the app to get started"
    var cycleDay: Int?
    var phase: String?
    var sleepMinutes: Int?
    var bedBy: String?
    var energy: Int?
    var streakNights: Int = 0
    var caffeineMg: Double = 0
    var caffeineDay: String = ""
    var updated = Date.distantPast
    // For the Watch screens.
    var restingHr: Int?
    var hrv: Int?
    var hrUp = false
    var hrvDown = false
    var typicalLength: Int?
    var periodLength: Int?
    var ovulationDay: Int?
    var daysToPeriod: Int?
    var tempDelta: Double?
    var caffeineAtBed: Double?
    var examNote: String?
    var sick = false
    var sickTonight: String?
    var darkAtNight = true
    var bedtimeMinutes: Int?
    /// Her water bottle size, so the Watch logs the right amount.
    var bottleMl: Double?
    /// Water today and the goal, both in bottles.
    var waterBottles: Double = 0
    var waterGoal: Double = 3
    var waterDay: String = ""

    static let appGroup = "group.com.ashleylibasci.healthdashboard"
    private static let key = "widgetSnapshot.v1"

    /// Fields added later fall back to defaults, so an older snapshot still decodes.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? d }
        name = v(.name, ""); recovery = v(.recovery, nil); recoveryLabel = v(.recoveryLabel, ""); headline = v(.headline, "Open the app to get started")
        cycleDay = v(.cycleDay, nil); phase = v(.phase, nil); sleepMinutes = v(.sleepMinutes, nil); bedBy = v(.bedBy, nil); energy = v(.energy, nil)
        streakNights = v(.streakNights, 0); caffeineMg = v(.caffeineMg, 0); caffeineDay = v(.caffeineDay, ""); updated = v(.updated, .distantPast)
        restingHr = v(.restingHr, nil); hrv = v(.hrv, nil); hrUp = v(.hrUp, false); hrvDown = v(.hrvDown, false)
        typicalLength = v(.typicalLength, nil); periodLength = v(.periodLength, nil); ovulationDay = v(.ovulationDay, nil); daysToPeriod = v(.daysToPeriod, nil)
        tempDelta = v(.tempDelta, nil); caffeineAtBed = v(.caffeineAtBed, nil); examNote = v(.examNote, nil); sick = v(.sick, false)
        sickTonight = v(.sickTonight, nil); darkAtNight = v(.darkAtNight, true); bedtimeMinutes = v(.bedtimeMinutes, nil)
        bottleMl = v(.bottleMl, nil)
        waterBottles = v(.waterBottles, 0); waterGoal = v(.waterGoal, 3); waterDay = v(.waterDay, "")
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> WidgetSnapshot? { try? JSONDecoder().decode(WidgetSnapshot.self, from: data) }

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Today's caffeine, reset to zero once the day changes.
    var caffeineToday: Double { caffeineDay == Self.eveningKey() ? caffeineMg : 0 }
    var waterToday: Double { waterDay == Self.calendarKey() ? waterBottles : 0 }

    /// Today's plain calendar date as "yyyy-MM-dd" (Gregorian), for daily totals like water.
    static func calendarKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Whether the numbers are from today; after midnight, yesterday's recovery shouldn't pass for today's.
    var isFromToday: Bool { Calendar.current.isDateInToday(updated) }

    /// Today's evening as "yyyy-MM-dd" in the Gregorian calendar (any phone calendar setting),
    /// where anything before 5am still counts as last night, matching the app.
    static func eveningKey(_ date: Date = .now) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let day = cal.component(.hour, from: date) < 5 ? cal.date(byAdding: .day, value: -1, to: date)! : date
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }
}
