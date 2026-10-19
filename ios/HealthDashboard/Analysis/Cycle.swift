import Foundation

struct Period: Equatable {
    var start: String
    var end: String
    var days: Int { Day.between(start, end) + 1 }
}

/// Bleeding days this close together belong to one period, so a few unlogged days in the
/// middle of a period don't start a new "cycle".
let periodGapDays = 6

/// Groups logged bleeding days into periods. Spotting is stored separately and never counts.
func periods(_ flow: [String: Int]) -> [Period] {
    let days = flow.filter { $0.value >= 2 }.keys.sorted()
    var out: [Period] = []
    for d in days {
        if let last = out.last, Day.between(last.end, d) <= periodGapDays {
            out[out.count - 1].end = d
        } else {
            out.append(Period(start: d, end: d))
        }
    }
    return out
}

/// Whether bleeding on `day` starts a new period: no bleeding logged in the days before it.
func startsNewPeriod(_ day: String, flow: [String: Int]) -> Bool {
    !(1...periodGapDays).contains { (flow[Day.shift(day, -$0)] ?? 0) >= 2 }
}

/// Lengths of complete cycles (start to next start), oldest first.
func cycleLengths(_ periods: [Period]) -> [Int] {
    zip(periods, periods.dropFirst()).map { Day.between($0.start, $1.start) }
}

enum CyclePhase: String, CaseIterable {
    case period = "Period", follicular = "Follicular", ovulation = "Ovulation", luteal = "Luteal"
}

struct CycleStatus: Equatable {
    var day: Int
    var lastStart: String
    var typicalLength: Int
    var lengthRange: ClosedRange<Int>?
    var periodLength: Int
    /// Day of the cycle ovulation happened, if a temperature rise showed it (natural cycles only).
    var ovulationDay: Int?
    var ovulationEstimated: Bool
    var nextStart: String?

    func phase(on day: Int) -> CyclePhase {
        let ov = ovulationDay ?? (typicalLength - 14)
        if day <= periodLength { return .period }
        if day < ov - 1 { return .follicular }
        if day <= ov + 1 { return .ovulation }
        return .luteal
    }

    var phase: CyclePhase { phase(on: day) }

    /// Whether today's phase can be trusted: a temperature rise showed ovulation, or the cycle is
    /// still within its usual length. Long irregular cycles don't get a phase guess.
    var phaseKnown: Bool { ovulationDay != nil || day <= typicalLength + 3 }

    /// Days past the expected start, once the period is late (natural cycles with a prediction only).
    var daysLate: Int? {
        guard let next = nextStart else { return nil }
        let late = Day.between(next, Day.key(.now))
        return late > 0 ? late : nil
    }
    /// The last 5 days before the expected period, when PMS-type changes are most common.
    var isLateLuteal: Bool { phase == .luteal && day >= typicalLength - 5 }
}

/// Where she is in a natural or irregular cycle. Predictions are only made for natural cycles
/// that are regular enough (range within 7 days); irregular cycles get no countdown.
func cycleStatus(_ flow: [String: Int], wristTemp: [String: Double], predict: Bool, today: String = Day.key(.now)) -> CycleStatus? {
    let ps = periods(flow)
    guard let last = ps.last, Day.between(last.start, today) >= 0 else { return nil }
    let lengths = Array(cycleLengths(ps).suffix(6))
    let typical = lengths.isEmpty ? 28 : Int(median(lengths.map(Double.init))!.rounded())
    let range = lengths.count >= 2 ? lengths.min()!...lengths.max()! : nil
    let regular = range.map { $0.upperBound - $0.lowerBound <= 7 } ?? true
    let periodLength = Int(median(ps.suffix(6).map { Double($0.days) }) ?? 5)
    let ovulation = temperatureShift(wristTemp, from: last.start, to: today)
    var next: String?
    if predict && regular { next = Day.shift(last.start, typical) }
    return CycleStatus(
        day: Day.between(last.start, today) + 1, lastStart: last.start, typicalLength: typical, lengthRange: range,
        periodLength: max(3, min(8, periodLength)), ovulationDay: ovulation, ovulationEstimated: ovulation == nil, nextStart: next
    )
}

/// The classic "3 over 6" rule: the first of three nights whose temperatures are all above the
/// highest of the six nights before, by at least 0.1°C. Returns the cycle day of ovulation (the night before).
func temperatureShift(_ temp: [String: Double], from start: String, to end: String) -> Int? {
    let span = Day.between(start, end)
    guard span >= 9 else { return nil }
    for d in 6...(span - 2) {
        let before = (1...6).compactMap { temp[Day.shift(start, d - $0)] }
        let after = (0...2).compactMap { temp[Day.shift(start, d + $0)] }
        guard before.count >= 5, after.count == 3, let high = before.max() else { continue }
        if after.allSatisfy({ $0 >= high + 0.1 }) { return d }
    }
    return nil
}

/// Wrist temperature vs. her own 60-day median, by date, for the chart.
func temperatureDeviation(_ temp: [String: Double], days: Int = 35, today: String = Day.key(.now)) -> [(date: String, value: Double)] {
    let base = median((0..<60).compactMap { temp[Day.shift(today, -$0)] })
    guard let base else { return [] }
    return (0..<days).reversed().compactMap { back in
        let d = Day.shift(today, -back)
        return temp[d].map { (d, round1($0 - base)) }
    }
}

struct PhaseStats: Equatable {
    var phase: CyclePhase
    var days: ClosedRange<Int>
    var sleep: Double?
    var restingHr: Double?
    var hrv: Double?
}

/// Her own averages in each phase across recent complete cycles, vs. her overall average.
func phaseStats(_ data: HealthData, cycles: Int = 6) -> [PhaseStats] {
    let ps = periods(data.flow)
    guard ps.count >= 2 else { return [] }
    let recent = Array(ps.suffix(cycles + 1))
    var buckets: [CyclePhase: (sleep: [Double], rhr: [Double], hrv: [Double])] = [:]
    var allSleep: [Double] = [], allRhr: [Double] = [], allHrv: [Double] = []
    let nightsByDate = Dictionary(data.nights.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    for (a, b) in zip(recent, recent.dropFirst()) {
        let length = Day.between(a.start, b.start)
        let ov = temperatureShift(data.wristTemp, from: a.start, to: Day.shift(b.start, -1)) ?? (length - 14)
        let status = CycleStatus(day: 1, lastStart: a.start, typicalLength: length, lengthRange: nil, periodLength: a.days, ovulationDay: ov, ovulationEstimated: false, nextStart: nil)
        for day in 1...length {
            let date = Day.shift(a.start, day - 1)
            let phase = status.phase(on: day)
            if let n = nightsByDate[date] { buckets[phase, default: ([], [], [])].sleep.append(Double(n.asleepMinutes)); allSleep.append(Double(n.asleepMinutes)) }
            if let v = data.restingHr[date] { buckets[phase, default: ([], [], [])].rhr.append(v); allRhr.append(v) }
            if let v = data.hrv[date] { buckets[phase, default: ([], [], [])].hrv.append(v); allHrv.append(v) }
        }
    }
    let typical = Int(median(cycleLengths(recent).map(Double.init)) ?? 28)
    // Very short averages (often from gaps in logging) can't be split into phases.
    guard typical >= 21 else { return [] }
    let ov = typical - 14
    let ranges: [CyclePhase: ClosedRange<Int>] = [.period: 1...5, .follicular: 6...(ov - 2), .ovulation: (ov - 1)...(ov + 1), .luteal: (ov + 2)...typical]
    func diff(_ xs: [Double]?, _ all: [Double]) -> Double? {
        guard let xs, xs.count >= 3, let a = mean(xs), let b = mean(all) else { return nil }
        return round1(a - b)
    }
    return CyclePhase.allCases.map { p in
        PhaseStats(phase: p, days: ranges[p]!, sleep: diff(buckets[p]?.sleep, allSleep), restingHr: diff(buckets[p]?.rhr, allRhr), hrv: diff(buckets[p]?.hrv, allHrv))
    }
}

/// Where she is in a 28-day pill, ring or patch pack: 21 active days, then a 7-day break.
struct PackStatus: Equatable {
    var day: Int
    var isBreakWeek: Bool { day > 21 }
    var nextBleed: String
}

func packStatus(packStart: Date?, today: String = Day.key(.now)) -> PackStatus? {
    guard let packStart else { return nil }
    let start = Day.key(packStart)
    let since = Day.between(start, today)
    guard since >= 0 else { return nil }
    let day = since % 28 + 1
    let cycleStart = Day.shift(today, -(day - 1))
    // The break week starts on pack day 22, whether or not it has started yet.
    let bleed = Day.shift(cycleStart, 21)
    return PackStatus(day: day, nextBleed: bleed)
}
