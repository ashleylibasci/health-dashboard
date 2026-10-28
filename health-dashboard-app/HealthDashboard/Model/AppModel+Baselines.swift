import Foundation
import HealthCore

/// Clean baselines (E1): "your usual" HRV, resting heart rate, breathing
/// and wrist temperature leave out the days one bad weekend would skew.
/// Alcohol drops next-night HRV and raises resting heart rate sharply, so
/// mixing those nights in makes ordinary days look "above usual". Nothing
/// new on screen; the usuals are just fairer.
extension AppModel {
    /// Standard drinks the evening before that leave the night out.
    static let baselineDrinks = 3.0
    /// Days after crossing time zones that are left out (the change day
    /// and the two after it, while her body clock catches up).
    static let travelDays = 3

    /// Symptoms that only come with being sick (the sick check's list,
    /// without tiredness and headache, which come with periods too).
    static let sickOnlySymptoms: Set<String> = Set(SickView.feelings).subtracting(SickView.shared)

    /// Calendar days (midnights) left out of every baseline: wake days
    /// after 3+ standard drinks, days she logged sick symptoms and the day
    /// after, and the first days after a time-zone change.
    func baselineExclusions(calendar cal: Calendar = .current) -> Set<Date> {
        var out = Set<Date>()
        func add(_ day: Date, through extra: Int = 0) {
            for i in 0...extra {
                if let d = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: day)) { out.insert(d) }
            }
        }
        // A night's drinks are logged 5pm–5am; its wake day is the day after
        // the evening (or the same day, after midnight).
        let evenings = Set(store.data.alcoholLog.map { cal.startOfDay(for: $0.date.addingTimeInterval(-5 * 3600)) })
        for evening in evenings {
            guard let wake = cal.date(byAdding: .day, value: 1, to: evening),
                  standardDrinks(beforeWakeDay: wake) >= Self.baselineDrinks else { continue }
            add(wake)
        }
        for entry in store.data.symptomLog where !Self.sickOnlySymptoms.isDisjoint(with: entry.symptoms) {
            add(entry.date, through: 1)
        }
        let zones = store.data.timeZoneByDay.sorted { $0.key < $1.key }
        for (previous, next) in zip(zones, zones.dropFirst()) where previous.value != next.value {
            add(next.key, through: Self.travelDays - 1)
        }
        return out
    }

    /// Notes today's time zone (once a day, or when it changes), so travel
    /// days can be left out of her baselines. Kept for 60 days.
    func recordTimeZone(now: Date = .now, calendar cal: Calendar = .current) {
        let today = cal.startOfDay(for: now)
        let zone = TimeZone.current.identifier
        guard store.data.timeZoneByDay[today] != zone else { return }
        var zones = store.data.timeZoneByDay
        zones[today] = zone
        if let cutoff = cal.date(byAdding: .day, value: -60, to: today) { zones = zones.filter { $0.key >= cutoff } }
        store.data.timeZoneByDay = zones
    }
}
