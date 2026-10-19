import Foundation

/// Hours of sleep the app counts as "enough" when adding up sleep debt.
let sleepNeedMinutes = 8 * 60

/// Minutes short of 8 hours for each of the last 7 nights, oldest first (0 when she got enough,
/// nil when there's no sleep recorded for that night).
func sleepDebt(_ nights: [Night], today: String = Day.key(.now)) -> [Int?] {
    let byDate = Dictionary(nights.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    return (1...7).reversed().map { k in byDate[Day.shift(today, -k)].map { max(0, sleepNeedMinutes - $0.asleepMinutes) } }
}

struct EnergyNow: Equatable {
    /// Rough share of energy left, 0–100.
    var left: Int
    var startedAt: Int
    var stressedHours: Int
    var activeKcal: Double
}

/// A simple "energy left" estimate: start the day at your recovery score, then spend some for
/// activity (about 1 point per 15 active kcal) and for each hour your heart ran stressed.
func energyNow(recovery: Int, activeKcal: Double, stressedHours: Int) -> EnergyNow {
    let left = Double(recovery) - activeKcal / 15 - Double(stressedHours) * 3
    return EnergyNow(left: Int(max(5, min(100, left)).rounded()), startedAt: recovery, stressedHours: stressedHours, activeKcal: activeKcal)
}

/// Today's active burn vs. the average of the 28 days before, as a fraction (1 = normal).
func loadVsNormal(_ activeKcal: [String: Double], today: String = Day.key(.now)) -> (ratio: Double, daysOfHistory: Int)? {
    let past = (1...28).compactMap { activeKcal[Day.shift(today, -$0)] }
    guard let now = activeKcal[today] else { return nil }
    guard past.count >= 14, let avg = mean(past), avg > 0 else { return (0, past.count) }
    // Scale the day so far up to a full day before comparing.
    let hour = Double(Calendar.current.component(.hour, from: .now)) + 1
    return (now / avg * 24 / max(8, hour), past.count)
}

/// About 2 liters a day from drinks is a common target for women; food covers the rest.
let waterGoalMl = 2000.0

/// Common reusable and store-bought bottle sizes.
let bottleSizes: [(name: String, ml: Double)] = [
    ("16.9 oz", 500), ("20 oz", 591), ("24 oz", 710), ("32 oz", 946), ("40 oz", 1183),
]

func bottleName(_ ml: Double) -> String {
    bottleSizes.first { abs($0.ml - ml) < 5 }?.name ?? "\(Int(ml)) mL"
}

/// Daily goal in bottles, rounded to the nearest quarter.
func goalBottles(_ bottleMl: Double) -> Double { max(1, (waterGoalMl / bottleMl * 4).rounded() / 4) }

/// "1¾", "2", "½"
func bottleCount(_ x: Double) -> String {
    let q = Int((x * 4).rounded())
    let whole = q / 4, frac = ["", "¼", "½", "¾"][q % 4]
    return whole == 0 && !frac.isEmpty ? frac : "\(whole)\(frac)"
}
