import Foundation

/// Caffeine's half-life in healthy adults is about 5 hours (it varies from 3 to 7).
let caffeineHalfLifeHours = 5.0
/// Under this much at bedtime is the goal; more tends to delay sleep.
let bedtimeCaffeineGoal = 25.0

/// The FDA's general guide: up to about 400 mg a day is not usually linked to harm in healthy adults.
let dailyCaffeineGuide = 400.0

/// A calm, specific note once today's total passes the daily guide.
func caffeineLimitNote(_ mg: Double) -> String? {
    guard mg > dailyCaffeineGuide else { return nil }
    return "That’s \(Int(mg)) mg today, past the 400 mg the FDA treats as a general daily guide for healthy adults. More can mean jitters, a racing heart and worse sleep tonight."
}

/// Milligrams still in the body at `time`, from every log before it.
func caffeineLeft(_ logs: [Reading], at time: Date) -> Double {
    logs.filter { $0.date <= time }.reduce(0) { total, log in
        total + log.value * pow(0.5, time.timeIntervalSince(log.date) / 3600 / caffeineHalfLifeHours)
    }
}

struct CutoffBucket: Equatable {
    var label: String
    var nights: Int
    var asleepMinutes: Double
}

struct CutoffTest: Equatable {
    /// Days with at least one log, out of the 21 the test needs.
    var daysLogged: Int
    var buckets: [CutoffBucket]
    var isReady: Bool { daysLogged >= 21 }
}

/// Compares each night's sleep with when that day's last caffeine was: before noon, noon–3pm, after 3pm.
func cutoffTest(_ logs: [Reading], nights: [Night]) -> CutoffTest {
    let lastByDay = Dictionary(grouping: logs, by: \.day).mapValues { $0.map(\.date).max()! }
    let nightByDate = Dictionary(nights.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    var groups: [Int: [Double]] = [:]
    for (day, last) in lastByDay {
        guard let night = nightByDate[day] else { continue }
        let hour = Calendar.current.component(.hour, from: last)
        groups[hour < 12 ? 0 : hour < 15 ? 1 : 2, default: []].append(Double(night.asleepMinutes))
    }
    let labels = ["Last caffeine before 12pm", "12–3pm", "After 3pm"]
    let buckets = (0..<3).compactMap { i in groups[i].map { CutoffBucket(label: labels[i], nights: $0.count, asleepMinutes: mean($0)!) } }
    return CutoffTest(daysLogged: lastByDay.count, buckets: buckets)
}

struct CaffeineDrink: Hashable {
    var name: String
    var mg: Double
}

/// Common drinks for quick logging, grouped the way they show up on screen. Amounts are typical
/// label values for the standard can or cup; homemade and café drinks vary.
let caffeineGroups: [(title: String, drinks: [CaffeineDrink])] = [
    ("Espresso", [CaffeineDrink(name: "1 shot", mg: 64), CaffeineDrink(name: "2 shots", mg: 128), CaffeineDrink(name: "3 shots", mg: 192)]),
    ("Energy drinks", [CaffeineDrink(name: "Red Bull", mg: 80), CaffeineDrink(name: "Monster", mg: 160), CaffeineDrink(name: "Celsius", mg: 200),
                       CaffeineDrink(name: "Alani Nu", mg: 200), CaffeineDrink(name: "Ghost", mg: 200), CaffeineDrink(name: "C4", mg: 200),
                       CaffeineDrink(name: "Prime Energy", mg: 200), CaffeineDrink(name: "Bang", mg: 300)]),
    ("Coffee & tea", [CaffeineDrink(name: "Drip coffee", mg: 95), CaffeineDrink(name: "Cold brew", mg: 200), CaffeineDrink(name: "Matcha", mg: 70),
                      CaffeineDrink(name: "Black tea", mg: 47), CaffeineDrink(name: "Diet Coke", mg: 46)]),
]
