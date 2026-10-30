import Foundation
import HealthCore

/// The nights behind the W / M / 6M trend charts (D-G2). A week and a month
/// come from the nights already read; six months reaches past them, so the
/// older nights are read from Apple Health only when she picks 6M, and
/// every number for the nights already read stays exactly as it was.
extension AppModel {
    struct TrendPoint: Identifiable, Hashable {
        var id: Date { date }
        var date: Date
        var hrv: Double?
        var restingHR: Double?
        var asleep: Int
    }

    /// Her nights in `range`, oldest first: the loaded nights plus `older`
    /// (from `olderTrendNights`) where those don't reach.
    func trendNights(_ range: TrendRange, older: [NightRecord] = []) -> [NightRecord] {
        let domain = range.domain()
        let earliest = nights.map(\.wakeDay).min() ?? .distantFuture
        return (older.filter { $0.wakeDay < earliest } + nights)
            .filter { $0.wakeDay >= domain.lowerBound && $0.wakeDay < domain.upperBound }
            .sorted { $0.wakeDay < $1.wakeDay }
    }

    /// HRV and resting heart rate rebuilt from each night's difference from
    /// her usual (as on every heart screen), and time asleep, for `range`.
    func bodyTrend(_ range: TrendRange, older: [NightRecord] = []) -> [TrendPoint] {
        let hrvBase = baselineHRV
        return trendNights(range, older: older).map { n in
            TrendPoint(date: n.wakeDay,
                       hrv: n.outcome.hrvDeltaPct.map { hrvBase * (1 + $0 / 100) },
                       restingHR: n.outcome.restingHRDelta.map { baselineRestingHR + $0 },
                       asleep: n.asleepMinutes)
        }
    }

    /// The nights before the loaded ones that six months needs. Read from
    /// Apple Health (with 30 days more heart readings, so the oldest nights
    /// have a usual to compare with), or, on example data, earlier copies of
    /// the example nights. Kept until the day or her nights change.
    func olderTrendNights() async -> [NightRecord] {
        let cal = Calendar.current
        let from = TrendRange.sixMonths.domain().lowerBound
        let earliest = nights.map(\.wakeDay).min() ?? cal.startOfDay(for: .now)
        guard earliest > from else { return [] }
        let key = "\(cal.startOfDay(for: .now).timeIntervalSince1970)-\(earliest.timeIntervalSince1970)-\(usingSampleData)"
        if let cached = Self.olderNightsCache, cached.key == key { return cached.nights }
        let older: [NightRecord]
        if usingSampleData {
            older = Self.repeatedBack(nights, to: from, calendar: cal)
        } else {
            let days = (cal.dateComponents([.day], from: from, to: .now).day ?? 182) + 1
            let main = Self.mainSleeps((try? await health.sleepSessions(days: days)) ?? [])
            let heart = await loadHeart(main: main, days: days + 30)
            older = main.map { night($0, heart: heart) }.filter { $0.wakeDay < earliest && $0.wakeDay >= from }
        }
        Self.olderNightsCache = (key, older)
        return older
    }

    /// Example nights reaching back to `from`: the example nights again,
    /// moved back whole four-week blocks, so weekends stay weekends and pack
    /// days stay pack days.
    private static func repeatedBack(_ nights: [NightRecord], to from: Date, calendar cal: Calendar) -> [NightRecord] {
        guard let first = nights.map(\.wakeDay).min(), let last = nights.map(\.wakeDay).max() else { return [] }
        let span = cal.dateComponents([.day], from: first, to: last).day ?? 0
        let block = max(28, (span + 1) / 28 * 28)
        var out: [NightRecord] = []
        var earliest = first
        var shift = block
        while earliest > from {
            let copies = nights.compactMap { n -> NightRecord? in
                guard let day = cal.date(byAdding: .day, value: -shift, to: n.wakeDay), day < earliest, day >= from else { return nil }
                var copy = n
                copy.wakeDay = day
                return copy
            }
            guard let oldest = copies.map(\.wakeDay).min() else { break }
            out += copies
            earliest = oldest
            shift += block
        }
        return out
    }

    private static var olderNightsCache: (key: String, nights: [NightRecord])?
}
