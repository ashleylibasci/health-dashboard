import Foundation

struct DrinkEffect: Equatable {
    var nights: Int
    var restingHr: Double?
    var hrv: Double?
    var remMinutes: Double?
    var recovery: Double?
    /// Recovery the day before, next day, day 2 and day 3, as a share of normal (1 = normal).
    var bounceBack: [Double]
}

/// Mornings after 3+ drinks vs. mornings after none, from her own data.
func drinkEffect(_ data: HealthData, recovery: [String: Int], minDrinks: Double = 3) -> DrinkEffect? {
    let perEvening = Dictionary(grouping: data.drinks) { r -> String in
        // A drink after midnight still belongs to the evening before.
        Calendar.current.component(.hour, from: r.date) < 6 ? Day.shift(r.day, -1) : r.day
    }.mapValues { $0.reduce(0) { $0 + $1.value } }
    let heavy = data.nights.filter { (perEvening[$0.date] ?? 0) >= minDrinks }
    let dry = data.nights.filter { perEvening[$0.date] == nil }
    guard heavy.count >= 2, dry.count >= 5 else { return nil }

    func diff(_ value: (Night) -> Double?) -> Double? {
        guard let a = mean(heavy.compactMap(value)), let b = mean(dry.compactMap(value)) else { return nil }
        return round1(a - b)
    }
    let normalRecovery = mean(dry.compactMap { recovery[$0.wakeDate].map(Double.init) })
    let bounce: [Double] = (-1...2).map { offset in
        guard let normal = normalRecovery, normal > 0, let v = mean(heavy.compactMap { recovery[Day.shift($0.wakeDate, offset)].map(Double.init) }) else { return 1 }
        return v / normal
    }
    return DrinkEffect(
        nights: heavy.count,
        restingHr: diff { data.restingHr[$0.wakeDate] },
        hrv: diff { data.hrv[$0.wakeDate] },
        remMinutes: diff { $0.stages.map { Double($0.rem) } },
        recovery: diff { recovery[$0.wakeDate].map(Double.init) },
        bounceBack: bounce
    )
}

/// Standard drinks for quick logging.
let alcoholDrinks = ["Wine", "Beer", "Seltzer", "Cocktail", "Shot"]
