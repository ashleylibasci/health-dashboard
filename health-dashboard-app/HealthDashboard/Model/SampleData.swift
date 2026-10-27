import Foundation
import HealthCore

/// Ashley's example data from the designs, used in the simulator, in
/// previews, and before Apple Health has enough nights.
enum SampleData {
    static let calendar = Calendar.current

    /// 71 nights whose next-day numbers stop improving at about 7h 50m.
    static func nights(endingOn today: Date = .now) -> [NightRecord] {
        var rng = Seeded(seed: 7)
        let day0 = calendar.startOfDay(for: today)
        return (1...71).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back + 1, to: day0)!
            let weekend = calendar.isDateInWeekend(day)
            let asleep = weekend ? 470 + rng.next() * 80 : 360 + rng.next() * 160
            let short = max(470 - asleep, 0) / 60
            let onset = weekend ? 82 + Int(rng.next() * 40) : 34 + Int(rng.next() * 30)
            return NightRecord(
                wakeDay: day, bedtime: onset - 12, sleepOnset: onset, wake: onset + Int(asleep),
                asleepMinutes: Int(asleep), alarmUsed: !weekend, wokeFromLightSleep: rng.next() > 0.25,
                outcome: NextDayOutcome(
                    hrvDeltaPct: 2 - 6 * short + (rng.next() - 0.5) * 3,
                    restingHRDelta: -1 + 2.2 * short + (rng.next() - 0.5),
                    checkIn: min(5, max(1, 4 - 0.55 * max(415 - asleep, 0) / 60 + (rng.next() - 0.5) * 0.6)),
                    energyScore: 74 - 10 * short + (rng.next() - 0.5) * 6))
        }
    }

    /// 60 mornings by wake time, matching "Your past wake-ups".
    static func mornings() -> [Morning] {
        var rng = Seeded(seed: 11)
        var out: [Morning] = []
        for (lo, hi, n, mean) in [(380, 418, 6, 2.3), (420, 470, 14, 3.2), (470, 510, 21, 4.0), (510, 570, 9, 3.6), (575, 625, 10, 3.0)] {
            for _ in 0..<n {
                let light = rng.next() > (lo == 470 ? 0.1 : 0.35)
                out.append(Morning(wake: lo + Int(rng.next() * Double(hi - lo)), wokeFromLightSleep: light,
                                   outcome: min(5, max(1, mean + (light ? 0.25 : -1.2) + (rng.next() - 0.5) * 1.1))))
            }
        }
        return out
    }

    /// Last week, Mon Oct 12 – Sun Oct 18 in the designs.
    static func lastWeek(endingBefore today: Date = .now) -> [DaySummary] {
        let rows: [(Int, Int, Int, Int, Bool, Int, Int, Int?)] = [
            (64, 400, 70, 482, false, 14, 200, 810), (69, 472, 10, 494, true, 24, 130, 585),
            (78, 483, 5, 500, true, 31, 130, 580), (71, 471, 25, 508, true, 22, 130, 615),
            (63, 418, 58, 488, true, 17, 210, 910), (48, 380, 160, 552, false, 8, 250, 820),
            (59, 470, 108, 590, true, 17, 70, 750)]
        let start = calendar.date(byAdding: .day, value: -8, to: calendar.startOfDay(for: today))!
        return rows.enumerated().map { i, r in
            DaySummary(date: calendar.date(byAdding: .day, value: i, to: start)!, energy: r.0, asleep: r.1, bedtime: r.2,
                       wake: r.3, wokeFromLightSleep: r.4, daylightMinutes: r.5, caffeineMg: r.6, lastCaffeine: r.7)
        }
    }

    static let lastNight = (bedtime: 30, onset: 42, wake: 441, asleep: 455, wokeFromLight: true)
    static let hrvDeltaPct = -6.0, restingHRDelta = 2.0, hrv = 43.0, restingHR = 70.0
    static let daylightToday = 18, stepsToday = 7820
    static let caffeineToday = [CaffeineDose(time: 580, mg: 130)]
    static let cycleDay = 22, cycleLength = 29
    static let workNights = [Chronotype.Night(onset: 34, wake: 490)]
    static let freeNights = [Chronotype.Night(onset: 82, wake: 618)]

    // Stress: calm morning, a spike at 3pm (studying), a run at 6pm (not stress).
    static let stressSamples: [StressModel.Sample] = (7...22).map { h in
        let hr: Double = [7: 66, 8: 72, 9: 74, 10: 76, 11: 75, 12: 73, 13: 74, 14: 79, 15: 86, 16: 80, 17: 74, 18: 128, 19: 78, 20: 75, 21: 72, 22: 68][h] ?? 72
        let hrv: Double = [14: 34, 15: 27, 16: 33][h] ?? 44
        return StressModel.Sample(hour: h, heartRate: hr, hrv: hrv, steps: h == 18 ? 4200 : 250)
    }
    static let baselineHRV = 46.0
    static let respiratoryRateDelta: Double? = 0.2
    static let wristTempDelta: Double? = 0.3
    static let vo2Max: Double? = 38.2
    static func vo2MaxHistory() -> [(date: Date, value: Double)] {
        let now = Date()
        return [(48, 41.0), (36, 40.2), (24, 39.4), (12, 38.8), (0, 38.2)].map { (calendar.date(byAdding: .month, value: -$0.0, to: now)!, $0.1) }
    }
    static let activeCalories = 420.0
    static let restingCalories = 1470.0

    /// Wake days (as offsets back from today) that followed a night with drinks.
    static let drinkNightOffsets: Set<Int> = [3, 10, 17, 24, 31, 38, 45]

    /// Last caffeine time and the next night's sleep, for the cutoff test.
    static let cutoffTest: [(lastCaffeine: Minutes?, asleep: Int)] = [
        (580, 500), (600, 495), (640, 505), (700, 490), (590, 500), (620, 510), (610, 498),
        (760, 478), (800, 470), (850, 475), (780, 482),
        (930, 420), (960, 430), (1000, 415)]

    struct Seeded {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }
}
