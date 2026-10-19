import Foundation

/// Signals that moved together over the last two mornings, a possible sign of a bug coming on.
struct SickSignals: Equatable {
    var restingHr: Double?
    var hrv: Double?
    var temperature: Double?
    var breathing: Double?
    var count: Int
    var confidence: String { count >= 4 ? "Higher confidence" : "Medium confidence" }
}

/// Compares the last two mornings with the 4 weeks before. Needs 3 of the 4 signals up to say anything.
/// When `lutealAdjust` is on, the temperature bar is raised by the usual luteal rise (about 0.3°C).
func sickSignals(_ data: HealthData, lutealAdjust: Bool, today: String = Day.key(.now)) -> SickSignals? {
    // Needs two weeks of history, so a new Watch's normal day-to-day swings don't look like illness.
    func change(_ series: [String: Double]) -> (last2: [Double], base: Double)? {
        let last2 = (0...1).compactMap { series[Day.shift(today, -$0)] }
        let history = (3...30).compactMap { series[Day.shift(today, -$0)] }
        guard last2.count == 2, history.count >= 14, let base = median(history) else { return nil }
        return (last2, base)
    }
    var rhr: Double?, hrv: Double?, temp: Double?, resp: Double?
    if let c = change(data.restingHr), c.last2.allSatisfy({ $0 - c.base >= 4 }) { rhr = round1(mean(c.last2)! - c.base) }
    if let c = change(data.hrv), c.base > 0, mean(c.last2)! / c.base - 1 <= -0.15 { hrv = mean(c.last2)! / c.base - 1 }
    if let c = change(data.wristTemp) {
        let rise = mean(c.last2)! - c.base - (lutealAdjust ? 0.3 : 0)
        if rise >= 0.4 { temp = round1(rise) }
    }
    if let c = change(data.respiratory), mean(c.last2)! - c.base >= 1.5 { resp = round1(mean(c.last2)! - c.base) }
    let count = [rhr, hrv, temp, resp].compactMap { $0 }.count
    // Drinks raise resting heart rate and temperature the next morning, so after 2+ drinks
    // all four signals have to move before calling it.
    let drinksLastNight = data.drinks.filter { $0.evening == Day.shift(today, -1) }.reduce(0) { $0 + $1.value }
    guard count >= (drinksLastNight >= 2 ? 4 : 3) else { return nil }
    return SickSignals(restingHr: rhr, hrv: hrv, temperature: temp, breathing: resp, count: count)
}

struct OffReason: Equatable {
    enum Kind { case sleep, body, cycle, caffeine, drinks, lateNight, exam, hrv }
    var kind: Kind
    var title: String
    var detail: String
    var weight: Double
}

/// Ranks the likely reasons someone feels off today by how far each is from their normal.
func offReasons(
    data: HealthData, sick: SickSignals?, cycle: CycleStatus?, exams: [CalendarEvent], hrvChange: Double?, today: String = Day.key(.now)
) -> [OffReason] {
    var out: [OffReason] = []
    if let n = data.nights.last, Day.between(n.wakeDate, today) <= 0, let typical = typicalSleep(data.nights, before: n.date) {
        let short = typical - Double(n.asleepMinutes)
        let debt = sleepDebt(data.nights, today: today).compactMap { $0 }.reduce(0, +)
        if short >= 30 || debt >= 120 {
            out.append(OffReason(kind: .sleep, title: short >= 30 ? "Short on sleep" : "Sleep debt this week", detail: "\(hoursMinutes(Double(n.asleepMinutes))) last night and \(hoursMinutes(Double(debt))) of sleep debt this week.", weight: max(short, Double(debt) / 3) / 30))
        }
        if n.bedtime >= lateBedtime {
            out.append(OffReason(kind: .lateNight, title: "A 2am night", detail: "You fell asleep at \(clockTime(Double(n.bedtime))). Late nights usually cost you the next day.", weight: 3))
        }
    }
    if let sick {
        out.append(OffReason(kind: .body, title: "Your body’s working harder", detail: [sick.restingHr.map { "Resting HR \(signed($0, ""))" }, sick.temperature.map { "temperature up \(String(format: "%.1f", $0))°" }].compactMap { $0 }.joined(separator: " and ") + " two mornings running.", weight: Double(sick.count) * 3))
    } else if let h = hrvChange, h <= -0.15 {
        out.append(OffReason(kind: .hrv, title: "Lower HRV than usual", detail: "\(Int((-h * 100).rounded()))% below your normal this morning, a sign your body is less recovered.", weight: -h * 15))
    }
    if let c = cycle {
        if c.isLateLuteal {
            out.append(OffReason(kind: .cycle, title: "Late luteal phase", detail: "Day \(c.day). This phase often lowers HRV a little and makes sleep lighter.", weight: 2))
        } else if c.phase == .period && c.day <= 2 {
            out.append(OffReason(kind: .cycle, title: "Day \(c.day) of your period", detail: "Cramps and lower iron can make the first days harder.", weight: 2.5))
        }
    }
    // Last night = yesterday's evening, including anything after midnight.
    let yesterday = Day.shift(today, -1)
    if let hour = data.caffeineLogs.filter({ $0.evening == yesterday }).map({ Day.eveningHour($0.date) }).max(), hour > 14 {
        out.append(OffReason(kind: .caffeine, title: "Late caffeine", detail: "Your last was at \(clockOfDay(Int(hour * 60) % 1440)) last night, past a 2pm cutoff.", weight: (hour - 14) * 1.5))
    }
    let lastNightDrinks = data.drinks.filter { $0.evening == yesterday }.reduce(0) { $0 + $1.value }
    if lastNightDrinks >= 2 {
        out.append(OffReason(kind: .drinks, title: "Drinks last night", detail: "\(Int(lastNightDrinks)) drinks. Your heart usually works harder the night after.", weight: lastNightDrinks))
    }
    if let exam = exams.first(where: { (-1...2).contains(Day.between(today, $0.date)) }) {
        let d = Day.between(today, exam.date)
        out.append(OffReason(kind: .exam, title: d < 0 ? "Exam yesterday" : "Exam coming up", detail: "\(exam.title) \(d < 0 ? "was yesterday" : d == 0 ? "is today" : d == 1 ? "is tomorrow" : "is in 2 days"). Stress shows up in your heart rate too.", weight: 2))
    }
    return Array(out.sorted { $0.weight > $1.weight }.prefix(4))
}

/// The single most useful thing to do about the top reason.
func oneThing(for reasons: [OffReason], bedtime: String) -> String {
    switch reasons.first?.kind {
    case .sleep?, .lateNight?: return "Be asleep by \(bedtime) tonight. It helps most of what’s on this list."
    case .body?, .hrv?: return "Take it easy: a walk instead of a workout, extra water, and an early night."
    case .cycle?: return "An earlier bedtime and an earlier last coffee help most this week."
    case .caffeine?: return "Keep today’s last coffee before 2pm."
    case .drinks?: return "Water through the day and an early night. Most people bounce back in two days."
    case .exam?: return "Protect tonight’s sleep; it does more for the exam than late studying."
    case nil: return "Nothing stands out. Keep your usual routine."
    }
}

// MARK: Streaks

struct Streaks: Equatable {
    var bedtimeTarget: Int
    var bedtimeNights: Int
    var caffeineDays: Int
    var waterDays: Int
}

/// Days in a row (ending today or yesterday) that pass `test`.
func streak(endingAt today: String, _ test: (String) -> Bool) -> Int {
    var day = test(today) ? today : Day.shift(today, -1)
    var count = 0
    while test(day) { count += 1; day = Day.shift(day, -1) }
    return count
}

func streaks(_ data: HealthData, bedtimeTarget: Int, today: String = Day.key(.now)) -> Streaks {
    let byDate = Dictionary(data.nights.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    let caffeineDays = Set(data.caffeine)
    return Streaks(
        bedtimeTarget: bedtimeTarget,
        bedtimeNights: streak(endingAt: Day.shift(today, -1)) { (byDate[$0]?.bedtime ?? .max) <= bedtimeTarget },
        caffeineDays: streak(endingAt: today) { caffeineDays.contains($0) },
        waterDays: streak(endingAt: today) { (data.waterMl[$0] ?? 0) >= waterGoalMl }
    )
}

struct Badge: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var symbol: String
    var earned: Bool
    var detail: String
}

func badges(_ data: HealthData, recovery: [RecoveryDay], exams: [CalendarEvent], streaks: Streaks) -> [Badge] {
    let nightsByWake = Dictionary(data.nights.map { ($0.wakeDate, $0) }, uniquingKeysWith: { a, _ in a })
    let examRested = exams.contains { e in (nightsByWake[e.date]?.asleepMinutes ?? 0) >= 420 }
    let fitness = fitnessSummary(data.vo2)
    let vo2Gain: Bool = {
        guard let last = data.vo2.last else { return false }
        let eightWeeksAgo = data.vo2.last { $0.date <= last.date.addingTimeInterval(-56 * 86400) }
        return eightWeeksAgo.map { last.value - $0.value >= 3 } ?? false
    }()
    _ = fitness
    return [
        Badge(name: "Early bird", symbol: "sunrise.fill", earned: data.nights.contains { $0.bedtime <= 5 * 60 }, detail: "Asleep by 11pm"),
        Badge(name: "First latte log", symbol: "cup.and.saucer.fill", earned: !data.caffeineLogs.isEmpty, detail: "Log caffeine once"),
        Badge(name: "Full cycle tracked", symbol: "circle.dashed", earned: periods(data.flow).count >= 2, detail: "Two periods logged"),
        Badge(name: "10k steps", symbol: "figure.walk", earned: data.steps.values.contains { $0 >= 10_000 }, detail: "One 10,000-step day"),
        Badge(name: "Hydrated week", symbol: "drop.fill", earned: streaks.waterDays >= 7, detail: "Water goal 7 days running"),
        Badge(name: "Exam survivor", symbol: "star.fill", earned: examRested, detail: "7h+ sleep before an exam"),
        Badge(name: "Recovery 90+", symbol: "heart.fill", earned: recovery.contains { $0.score >= 90 }, detail: "A recovery score of 90"),
        Badge(name: "30-night streak", symbol: "moon.stars.fill", earned: streaks.bedtimeNights >= 30, detail: "30 nights on your bedtime"),
        Badge(name: "VO₂ +3", symbol: "bolt.heart.fill", earned: vo2Gain, detail: "VO₂ max up 3 in 8 weeks"),
    ]
}
