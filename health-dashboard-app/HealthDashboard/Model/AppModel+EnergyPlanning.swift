import Foundation
import HealthCore

/// Derived values for the energy and planning screens (Energy, body clock,
/// clock change, weekly recap, exam week). Display-only helpers; the models
/// themselves live in HealthCore.
extension AppModel {

    // MARK: Energy drivers

    /// One thing pushing today's energy score up or down, in points.
    struct EnergyDriver: Identifiable, Hashable {
        var id: String { name }
        /// "Sleep debt 2h 40m"
        var name: String
        /// Short phrase for sentences: "sleep debt".
        var cause: String
        var points: Int

        /// "+2", "−7" (true minus sign), "0".
        var deltaText: String {
            if points > 0 { return "+\(points)" }
            if points < 0 { return "\u{2212}\(abs(points))" }
            return "0"
        }
    }

    /// What moved today's energy score, from the energy model itself: each
    /// input it uses (last night's sleep, sleep debt, waking from deep sleep,
    /// wake time against her body clock) compared with a neutral value.
    /// Inputs the model doesn't use (recovery, daylight, cycle) aren't listed.
    var energyDrivers: [EnergyDriver] {
        let need = sleepNeed.minutes
        return EnergyModel.drivers(energyToday.input, need: need).map { d in
            switch d.kind {
            case .lastNight:
                let short = d.amount < need
                return EnergyDriver(name: "Slept \(Clock.duration(d.amount)) (need \(Clock.duration(need)))",
                                    cause: short ? "a short night" : "a long night", points: d.points)
            case .sleepDebt:
                return EnergyDriver(name: "Sleep debt \(Clock.duration(d.amount))", cause: "sleep debt", points: d.points)
            case .wokeFromDeepSleep:
                return EnergyDriver(name: "Woke from deep sleep", cause: "waking mid-cycle", points: d.points)
            case .wakeTime:
                let later = d.amount > 0
                return EnergyDriver(name: "Woke \(Clock.duration(abs(d.amount))) \(later ? "later" : "earlier") than your body clock",
                                    cause: later ? "a late wake" : "an early wake", points: d.points)
            }
        }
    }

    // MARK: Body clock

    /// Average sleep window on work (alarm) nights, relative to wake-day midnight.
    var workNightWindow: TimeRange? { Self.averageWindow(workNights) }
    /// Average sleep window on free nights.
    var freeNightWindow: TimeRange? { Self.averageWindow(freeNights) }

    static func averageWindow(_ nights: [Chronotype.Night]) -> TimeRange? {
        guard !nights.isEmpty else { return nil }
        let n = Double(nights.count)
        let onset = Double(nights.map(\.onset).reduce(0, +)) / n
        let wake = Double(nights.map(\.wake).reduce(0, +)) / n
        return TimeRange(Int(onset.rounded()), Int(wake.rounded()))
    }

    /// When she'd wake with no alarm: the corrected mid-sleep plus half her
    /// weekly average sleep.
    var naturalWake: Minutes? {
        guard let c = chronotype else { return nil }
        return c.midSleepFreeCorrected + c.weeklyAverageSleep / 2
    }

    /// True for intermediate types and later.
    var isEveningLeaning: Bool {
        guard let c = chronotype else { return true }
        switch c.category {
        case .veryEarly, .moderateMorning: return false
        default: return true
        }
    }

    // MARK: Clock change (US: first Sunday of November)

    /// The next US fall-back date (today counts if it's today).
    var nextFallBack: Date { Self.fallBackDate(after: .now) }

    static func fallBackDate(after now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        for y in [year, year + 1] {
            if let date = firstSundayOfNovember(y, calendar: calendar), date >= today { return date }
        }
        return today
    }

    static func firstSundayOfNovember(_ year: Int, calendar: Calendar) -> Date? {
        guard let nov1 = calendar.date(from: DateComponents(year: year, month: 11, day: 1)) else { return nil }
        let weekday = calendar.component(.weekday, from: nov1)   // 1 = Sunday
        let offset = (8 - weekday) % 7
        return calendar.date(byAdding: .day, value: offset, to: nov1)
    }

    /// The moment the clocks go back on `nextFallBack` (2:00am on the old
    /// clock, two elapsed hours after midnight).
    var fallBackInstant: Date { Calendar.current.startOfDay(for: nextFallBack).addingTimeInterval(2 * 3600) }
    /// The clocks have gone back already today (it's after 2am that Sunday).
    var fallBackHasHappened: Bool { Date() >= fallBackInstant }

    var daysUntilFallBack: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: nextFallBack)).day ?? 0
    }

    // MARK: Usual values (last 30 nights)

    private var recentNights: [NightRecord] {
        Array(nights.sorted { $0.wakeDay > $1.wakeDay }.prefix(30))
    }

    /// Average minutes asleep over the last 30 nights.
    var usualAsleep: Int? {
        let xs = recentNights.map { Double($0.asleepMinutes) }
        return xs.mean.map { Int($0.rounded()) }
    }

    /// Typical time she falls asleep, minutes after midnight (0..<1440).
    var usualSleepOnset: Minutes? {
        Clock.circularMean(recentNights.map(\.sleepOnset))
    }

    /// Resting heart rate baseline.
    var usualRestingHR: Double { restingHR - restingHRDelta }
}
