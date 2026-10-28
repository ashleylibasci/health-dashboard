import Foundation

// MARK: - Birth control and the cycle

public enum BirthControl: String, Codable, Sendable, CaseIterable {
    case combinedPill = "Combined pill"
    case miniPill = "Mini pill"
    case hormonalIUD = "Hormonal IUD"
    case copperIUD = "Copper IUD"
    case implant = "Implant"
    case shot = "Shot"
    case ring = "Ring"
    case patch = "Patch"

    public enum Ovulation: String, Sendable { case stopped, sometimes, mostStill, natural }

    /// Whether this method usually stops ovulation.
    public var ovulation: Ovulation {
        switch self {
        case .combinedPill, .implant, .shot, .ring, .patch: .stopped
        case .miniPill: .sometimes
        case .hormonalIUD: .mostStill
        case .copperIUD: .natural
        }
    }

    /// Methods taken in a monthly pack with a break week (bleed on the break).
    public var hasBreakWeek: Bool { self == .combinedPill || self == .ring || self == .patch }

    public var note: String {
        switch self {
        case .combinedPill: "Estrogen and progestin. Stops ovulation; the bleed in your break week is a withdrawal bleed, not a period."
        case .miniPill: "Progestin only. Ovulation stops in some people and not others, and bleeding can be unpredictable."
        case .hormonalIUD: "Progestin released in the uterus. Most people still ovulate, so cycle phases still apply; periods are often lighter or stop."
        case .copperIUD: "No hormones. You ovulate normally; periods can be heavier."
        case .implant: "Progestin under the skin. Stops ovulation; bleeding varies a lot."
        case .shot: "Progestin every 12–13 weeks. Stops ovulation; periods often stop."
        case .ring: "Like the combined pill: stops ovulation, with a bleed in the ring-free week."
        case .patch: "Like the combined pill: stops ovulation, with a bleed in the patch-free week."
        }
    }
}

/// What the cycle screen should show, given setup and birth control.
public enum CycleDisplay: Hashable, Sendable {
    /// Natural cycle (or a method that keeps ovulation): phases apply.
    case phases(day: Int, length: Int, phase: CyclePhase)
    /// Natural cycle running past her usual length (more than 3 days over).
    /// No phase, no "period expected" countdown and no luteal adjustments:
    /// the app can't tell where in the cycle she is.
    case overdue(day: Int, typicalLength: Int)
    /// Pill, ring or patch: active days and a break week, no ovulation.
    /// With continuous use (`activeDays == packLength`) there is no break week.
    case pack(day: Int, activeDays: Int, packLength: Int)
    /// Implant or shot (or a pack method with no pack position known yet):
    /// no cycle phases; bleeding may be irregular or absent.
    case suppressed(BirthControl)
    /// Irregular cycles or PCOS: no countdowns or predictions.
    case irregular(daysSinceLastPeriod: Int?)
    case notTracking

    /// Days past her usual length before a natural cycle counts as overdue.
    public static let overdueGraceDays = 3

    /// The pack day a withdrawal bleed usually starts on: about 3 days into
    /// the break (day 24 of a 21+7 pack, day 27 of a 24+4 pack). The one rule
    /// used everywhere a bleed is placed in a pack.
    public static func bleedStartPackDay(activeDays: Int, packLength: Int) -> Int {
        min(max(activeDays, 1) + 3, max(packLength, 1))
    }

    /// The birth-control method decides first (pill/ring/patch → pack,
    /// implant/shot → suppressed), then irregular/PCOS, then phases.
    /// `packDay` is where she is in the current pack (1…packLength). Without
    /// it a pack method shows `.suppressed` ("set where you are in your
    /// pack"); a bleed date is never turned into a pack day here.
    /// The hormonal IUD and mini pill keep phases while the cycle is within
    /// her usual length, but a long gap is expected on them (bleeding often
    /// gets lighter or stops), so they never show `.overdue`.
    public static func make(tracking: Bool, irregular: Bool, birthControl: BirthControl?, cycleDay: Int?, cycleLength: Int,
                            packDay: Int? = nil, activeDays: Int? = nil, packLength: Int? = nil,
                            periodLength: Int = CycleEstimator.typicalPeriodLength) -> CycleDisplay {
        guard tracking else { return .notTracking }
        if let bc = birthControl {
            if bc.hasBreakWeek {
                let length = max(packLength ?? 28, 1)
                let active = min(max(activeDays ?? 21, 1), length)
                guard let r = packDay else { return .suppressed(bc) }
                let day = ((r - 1) % length + length) % length + 1
                return .pack(day: day, activeDays: active, packLength: length)
            }
            if bc.ovulation == .stopped { return .suppressed(bc) }
        }
        // Hormonal IUD or mini pill with no period logged: periods often stop,
        // so her method's own view, never "log your next period" (round 3, J1).
        if cycleDay == nil, let bc = birthControl, bc == .hormonalIUD || bc == .miniPill { return .suppressed(bc) }
        if irregular { return .irregular(daysSinceLastPeriod: cycleDay.map { $0 - 1 }) }
        guard let d = cycleDay else { return .irregular(daysSinceLastPeriod: nil) }
        if d > cycleLength + overdueGraceDays {
            if let bc = birthControl, bc == .hormonalIUD || bc == .miniPill { return .suppressed(bc) }
            return .overdue(day: d, typicalLength: cycleLength)
        }
        return .phases(day: d, length: cycleLength, phase: CycleEstimator.phase(day: d, length: cycleLength, periodLength: periodLength))
    }

    /// Phases, but past her usual length (the 3 grace days before overdue):
    /// the period is "due around now". No countdown and no luteal adjustments.
    public var isPastUsualLength: Bool {
        if case let .phases(day, length, _) = self { return day > length }
        return false
    }

    /// A natural cycle is (or may be) running but the app can't tell which
    /// phase she's in: irregular/PCOS, overdue, the grace days past her usual
    /// length, or a method that may keep ovulation once phases aren't shown.
    /// The app gives no luteal allowance then (it doesn't assume a phase it
    /// can't see) but says the cycle might be part of a change.
    public var cyclePhaseUnknown: Bool {
        switch self {
        case .irregular, .overdue: return true
        case let .phases(day, length, _): return day > length
        case let .suppressed(bc): return bc.ovulation != .stopped
        case .pack, .notTracking: return false
        }
    }

    /// Whether the late-luteal sleep adjustment applies (never when overdue).
    public var isLateLuteal: Bool {
        if case let .phases(day, length, _) = self { return day <= length && CycleEstimator.isLateLuteal(day: day, length: length) }
        return false
    }

    /// Pack methods: whether this pack has a break week at all.
    public var hasBreakWeek: Bool {
        if case let .pack(_, active, length) = self { return active < length }
        return false
    }

    /// Pack methods: whether today is in the break (withdrawal bleed) week.
    public var isBreakWeek: Bool {
        if case let .pack(day, active, length) = self { return active < length && day > active }
        return false
    }

    /// Pack methods: days until the break week starts (0 while in it), nil with
    /// continuous use (no break week, so no withdrawal bleed is due).
    public var daysToBreak: Int? {
        guard case let .pack(day, active, length) = self, active < length else { return nil }
        return day > active ? 0 : active - day + 1
    }
}

// MARK: - Stress

/// Daytime stress from heart rate and HRV while not moving, compared with
/// her own resting baseline. Hours with real activity are left out, so a
/// workout doesn't count as stress.
public struct StressDay: Hashable, Sendable {
    public struct Hour: Hashable, Sendable {
        public var hour: Int          // 0–23
        public var level: Int?        // 0–100, nil if asleep, active or no data
        public var active: Bool
        public var asleep: Bool = false
        /// The hour right after an active one: heart rate is still coming
        /// down from the workout, so it isn't counted as stress.
        public var coolingDown: Bool = false
    }
    /// The one label set used everywhere stress is named. The bands are
    /// fixed points on the 0–100 level, so the middle one is "Moderate", not
    /// "Usual": it isn't a personal baseline (Sam N14).
    public enum Label: String, Sendable, CaseIterable { case low = "Low", usual = "Moderate", raised = "Raised", high = "High" }

    public var hours: [Hour]
    /// Average over awake, still hours only.
    public var average: Int?
    public var label: Label?
    public var peak: Hour?
    public var calmestStretch: TimeRange?
    /// How many hours the average is built from.
    public var countedHours: Int { hours.filter { $0.level != nil }.count }
}

public enum StressModel {
    public struct Sample: Sendable {
        public var hour: Int
        public var heartRate: Double?
        public var hrv: Double?
        public var steps: Double
        /// Active energy burned that hour (kcal). Catches workouts without
        /// steps: swimming, cycling, lifting.
        public var activeKcal: Double
        /// She was asleep for most of the hour.
        public var asleep: Bool
        public init(hour: Int, heartRate: Double?, hrv: Double?, steps: Double, activeKcal: Double = 0, asleep: Bool = false) {
            self.hour = hour; self.heartRate = heartRate; self.hrv = hrv; self.steps = steps
            self.activeKcal = activeKcal; self.asleep = asleep
        }
    }

    /// An hour counts as active (left out) above this many steps…
    public static let activeSteps = 600.0
    /// …or this much active energy. A still hour burns roughly 5–20 kcal.
    /// This is the fallback for about a 60 kg woman; `activeKcal(bodyMassKg:)`
    /// scales it to her weight.
    public static let activeKcal = 60.0

    /// An active hour for her: about 1 kcal per kg of body weight (round 4,
    /// Ruiz F6), kept between 45 and 100 kcal. Without a weight, 60 kcal.
    public static func activeKcal(bodyMassKg: Double?) -> Double {
        guard let kg = bodyMassKg, kg > 0 else { return activeKcal }
        return min(max(kg * 1.0, 45), 100)
    }

    /// The luteal phase of a natural cycle raises heart rate at rest by about
    /// this much on its own (round 4, Laurent F3, Brandt F5).
    public static let lutealHeartRate = 2.0
    /// …and lowers HRV by about this share.
    public static let lutealHRVPct = 5.0

    /// Her own heart rate in still, awake hours over the last two weeks: the
    /// baseline stress is measured from when there's enough of it.
    public struct StillBaseline: Hashable, Sendable {
        public var median: Double
        /// Day-to-day spread, kept between 4 and 10 bpm so a very steady or
        /// very jumpy fortnight doesn't make the scale too tight or too loose.
        public var spread: Double
        public init(median: Double, spread: Double) { self.median = median; self.spread = spread }
    }

    /// Still hours needed before her own still-hour baseline is used.
    public static let stillHoursNeeded = 30

    /// From the heart rate of past still, awake hours (one value per hour).
    /// Nil with fewer than `stillHoursNeeded`.
    public static func stillBaseline(heartRates: [Double]) -> StillBaseline? {
        guard heartRates.count >= stillHoursNeeded, let m = heartRates.median, let sd = heartRates.standardDeviation else { return nil }
        return StillBaseline(median: m, spread: min(max(sd, 4), 10))
    }

    /// Bands on the 0–100 level, which is already relative to her own resting
    /// heart rate and HRV baseline.
    public static func label(for level: Int) -> StressDay.Label {
        level < 20 ? .low : level < 40 ? .usual : level < 60 ? .raised : .high
    }

    /// `restingHR` is her resting heart rate baseline. Without one (0), and
    /// without a still-hour baseline, there is nothing to compare against, so
    /// no hour gets a level and there is no label: "no data", never "High".
    /// With `still` (her own still-hour heart rate), an hour's heart rate is
    /// scored as (heart rate − her still median) / (3 × her spread), so
    /// three spreads above her usual still pace is the top. Without it, 25
    /// beats above resting is the top. `luteal`: the second half of a
    /// natural cycle, which takes 2 bpm off heart rate and expects 5% lower
    /// HRV. `activeKcal`: her active-hour threshold.
    public static func day(_ samples: [Sample], restingHR: Double, baselineHRV: Double, still: StillBaseline? = nil,
                           luteal: Bool = false, activeKcal: Double = activeKcal) -> StressDay {
        let activeHours = Set(samples.filter { !$0.asleep && ($0.steps > activeSteps || $0.activeKcal >= activeKcal) }.map(\.hour))
        let hasBaseline = restingHR > 0 || still != nil
        let hrAllowance = luteal ? lutealHeartRate : 0
        let hrvBase = baselineHRV * (luteal ? 1 - lutealHRVPct / 100 : 1)
        let hours: [StressDay.Hour] = samples.map { s in
            let active = activeHours.contains(s.hour)
            let coolingDown = !active && !s.asleep && activeHours.contains(s.hour - 1)
            guard hasBaseline, !s.asleep, !active, !coolingDown, s.heartRate != nil || s.hrv != nil else {
                return .init(hour: s.hour, level: nil, active: active && !s.asleep, asleep: s.asleep, coolingDown: coolingDown)
            }
            var parts: [Double] = []
            if let hr = s.heartRate {
                let h = hr - hrAllowance
                if let still {
                    parts.append(min(max((h - still.median) / (3 * still.spread), 0), 1))      // 3 spreads above her still pace = max
                } else {
                    parts.append(min(max((h - restingHR) / 25, 0), 1))                          // +25 bpm at rest = max
                }
            }
            if let v = s.hrv, hrvBase > 0 { parts.append(min(max((hrvBase - v) / (hrvBase * 0.5), 0), 1)) } // half baseline = max
            guard !parts.isEmpty else { return .init(hour: s.hour, level: nil, active: false) }
            let level = Int(((parts.reduce(0, +) / Double(parts.count)) * 100).rounded())
            return .init(hour: s.hour, level: level, active: false)
        }
        let levels = hours.compactMap(\.level).map(Double.init)
        let avg = levels.mean.map { Int($0.rounded()) }
        let label: StressDay.Label? = avg.map(label(for:))
        let peak = hours.filter { $0.level != nil }.max { ($0.level ?? 0) < ($1.level ?? 0) }
        // Calmest two-hour stretch between 8am and 10pm.
        var calm: (Int, Double)?
        for h in 8...20 {
            let pair = hours.filter { $0.hour == h || $0.hour == h + 1 }.compactMap(\.level)
            guard pair.count == 2 else { continue }
            let m = Double(pair.reduce(0, +)) / 2
            if calm == nil || m < calm!.1 { calm = (h, m) }
        }
        return StressDay(hours: hours, average: avg, label: label, peak: peak,
                         calmestStretch: calm.map { TimeRange($0.0 * 60, ($0.0 + 2) * 60) })
    }
}

// MARK: - Might be getting sick

/// Signals that the body is fighting something: resting heart rate up, HRV
/// down, breathing rate up, wrist temperature up, all against her own
/// baseline. In the luteal phase resting heart rate, HRV and wrist
/// temperature all shift a little on their own, and the morning after hard
/// training resting heart rate and HRV do too, so those count for less then.
public struct IllnessSignal: Hashable, Sendable {
    /// How likely it is she's fighting something (not how good the data is).
    /// The words count signs rather than claim a probability (round 4, Liu
    /// 15): the check can't say how likely illness is.
    public enum Confidence: String, Sendable, CaseIterable { case none = "All clear", low = "A little off", medium = "A couple of signs", high = "Several signs" }
    public struct Factor: Hashable, Sendable {
        public var name: String
        public var change: String
        public var flagged: Bool
        public var note: String?
    }
    public var confidence: Confidence
    public var factors: [Factor]
    /// Her cycle phase isn't known (irregular, PCOS, overdue…), so a rise
    /// from the second half of her cycle can't be ruled out. Screens and
    /// alerts should say so. Whether an allowance was applied depends on the
    /// `cyclePhaseUnknown` argument to `evaluate` (the app passes false and
    /// sets this flag afterwards, for the wording only).
    public var cyclePhaseUnknown: Bool = false

    /// `cyclePhaseUnknown`: a natural cycle whose phase the app can't tell.
    /// When true it gets the same allowances as the luteal phase and the
    /// result says so. The app passes false (round 3, H4): no allowance for a
    /// phase it can't see, so the sick check matches Today and "Why off".
    ///
    /// Cutoffs scale with her own spread when it's known (round 4, Brandt
    /// F6): resting heart rate counts at max(4, 2 × her spread) bpm, HRV at
    /// −max(15%, 1.5 × her spread). `periodDay` (the first week of a natural
    /// period, when resting heart rate runs low and HRV high) lowers both by
    /// 1 bpm and 3%. The smaller "moved a little" steps are half of those.
    public static func evaluate(restingHRDelta: Double, hrvDeltaPct: Double, respiratoryRateDelta: Double?, wristTempDelta: Double?,
                                lutealPhase: Bool, hardTrainingYesterday: Bool = false, cyclePhaseUnknown: Bool = false,
                                periodDay: Bool = false, restingHRSpread: Double? = nil, hrvSpreadPct: Double? = nil) -> IllnessSignal {
        var score = 0.0
        var factors: [Factor] = []
        let cycleAllowance = lutealPhase || cyclePhaseUnknown
        // Allowances: luteal adds ~2 bpm / −5% HRV; hard training ~3 bpm / −10%.
        let rhrAllowance = (cycleAllowance ? 2.0 : 0) + (hardTrainingYesterday ? 3.0 : 0)
        let hrvAllowance = (cycleAllowance ? 5.0 : 0) + (hardTrainingYesterday ? 10.0 : 0)
        let early = periodDay && !cycleAllowance
        let rhrCut = max(4, 2 * (restingHRSpread ?? 0)) - (early ? 1 : 0)
        let hrvCut = max(15, 1.5 * (hrvSpreadPct ?? 0)) - (early ? 3 : 0)
        let rhrSmall = rhrCut / 2, hrvSmall = hrvCut * 8 / 15
        let cycleNote = lutealPhase ? "Expected in this phase of your cycle" : "Could be your cycle: the app can't tell which phase you're in"
        func context(_ raw: Bool, _ counted: Bool) -> String? {
            guard raw && !counted else { return nil }
            if hardTrainingYesterday { return "Expected after yesterday's hard training" }
            if cycleAllowance { return cycleNote }
            return nil
        }

        let rhr = restingHRDelta >= rhrCut + rhrAllowance
        score += rhr ? 1 : (restingHRDelta >= rhrSmall + rhrAllowance ? 0.4 : 0)
        factors.append(.init(name: "Resting heart rate", change: String(format: "%+.0f bpm", restingHRDelta), flagged: rhr,
                             note: context(restingHRDelta >= rhrSmall, rhr)))
        let hrv = hrvDeltaPct <= -hrvCut - hrvAllowance
        score += hrv ? 1 : (hrvDeltaPct <= -hrvSmall - hrvAllowance ? 0.4 : 0)
        factors.append(.init(name: "HRV", change: String(format: "%+.0f%%", hrvDeltaPct), flagged: hrv,
                             note: context(hrvDeltaPct <= -hrvSmall, hrv)))
        if let rr = respiratoryRateDelta {
            let up = rr >= 1
            score += up ? 1 : 0
            factors.append(.init(name: "Breathing rate", change: String(format: "%+.1f/min", rr), flagged: up, note: nil))
        }
        if let t = wristTempDelta {
            let up = t >= (cycleAllowance ? 0.6 : 0.4)
            score += up ? 1 : 0
            factors.append(.init(name: "Wrist temperature", change: String(format: "%+.1f°C", t), flagged: up,
                                 note: cycleAllowance && t > 0.2 && !up ? cycleNote : nil))
        }
        let c: Confidence = score >= 3 ? .high : score >= 2 ? .medium : score >= 1.2 ? .low : .none
        return IllnessSignal(confidence: c, factors: factors, cyclePhaseUnknown: cyclePhaseUnknown && !lutealPhase)
    }

    /// Hard training is about this many active kcal per kg of body weight
    /// (round 4, Brandt F7, Ruiz F6)…
    public static let hardKcalPerKg = 8.0
    /// …and never counts below this many, however low her usual is.
    public static let hardFloorKcalPerKg = 5.0
    /// The weight used when Apple Health has none (about a typical young
    /// woman's, so 480 and 300 kcal).
    public static let typicalBodyMassKg = 60.0

    /// Whether yesterday was a hard training day for her: active energy at
    /// least 1.5× her own usual (the median of earlier days) and at least
    /// 5 kcal per kg of her weight. With fewer than 5 earlier days, about
    /// 8 kcal per kg. `bodyMassKg` from Apple Health; 60 kg without it.
    public static func isHardTraining(yesterdayKcal: Double?, earlierDaysKcal: [Double], bodyMassKg: Double? = nil) -> Bool {
        guard let y = yesterdayKcal else { return false }
        let kg = (bodyMassKg ?? 0) > 0 ? bodyMassKg! : typicalBodyMassKg
        let usable = earlierDaysKcal.filter { $0 > 0 }
        guard usable.count >= 5, let usual = usable.median else { return y >= kg * hardKcalPerKg }
        return y >= max(kg * hardFloorKcalPerKg, usual * 1.5)
    }
}

// MARK: - Fitness age

/// Fitness age from VO2 max: the age at which a typical woman has her VO2
/// max. Women only (the app is for women). The norms are the FRIEND
/// registry's treadmill tests of US women (Kaminsky 2015, Mayo Clin Proc,
/// Table 3), the reference Apple uses too: the median for each decade from
/// the 20s to the 70s, placed at the decade's middle (25, 35 … 75) and
/// joined by straight lines. Below 25 the line is held at the 20s median,
/// so the youngest fitness age is 25 ("Under 25", `isTopOfChart`).
/// A Watch estimate is often off by 5 or more points, so the fitness age
/// is shown as a range (`range`) and the level bands are a quarter of
/// women wide (round 4, Brandt F1–F3, Liu 2).
public enum FitnessAge {
    /// Decade middles and FRIEND 2015 women's 25th, 50th and 75th
    /// percentiles (ml/kg/min) for the 20s, 30s, 40s, 50s, 60s and 70s.
    static let ages: [Double] = [25, 35, 45, 55, 65, 75]
    static let p25: [Double] = [30.5, 25.3, 22.1, 19.9, 17.2, 15.6]
    static let p50: [Double] = [37.6, 30.2, 26.7, 23.4, 20.0, 18.3]
    static let p75: [Double] = [44.7, 36.1, 32.4, 27.6, 23.8, 20.8]

    /// The youngest fitness age the norms can give.
    public static let youngest = 25
    public static let oldest = 90
    /// How far a Watch estimate is often off (ml/kg/min); sets the range.
    public static let watchError = 5.0

    /// The median VO2 max at `age`: held at the 20s median up to 25, then
    /// along the decade medians, and past 75 on along the last slope.
    public static func average(age: Int) -> Double { median(atAge: Double(age)) }

    static func median(atAge a: Double) -> Double {
        if a <= ages[0] { return p50[0] }
        for i in 1..<ages.count where a <= ages[i] {
            let t = (a - ages[i - 1]) / (ages[i] - ages[i - 1])
            return p50[i - 1] + (p50[i] - p50[i - 1]) * t
        }
        let n = ages.count - 1
        let slope = (p50[n] - p50[n - 1]) / (ages[n] - ages[n - 1])
        return max(p50[n] + slope * (a - ages[n]), 1)
    }

    /// 25…90: the age on the median line with her VO2 max. At 25, check
    /// `isTopOfChart` and show "Under 25".
    public static func estimate(vo2Max v: Double) -> Int {
        if v >= p50[0] { return youngest }
        var age: Double
        if let i = (1..<ages.count).first(where: { v >= p50[$0] }) {
            let t = (p50[i - 1] - v) / (p50[i - 1] - p50[i])
            age = ages[i - 1] + (ages[i] - ages[i - 1]) * t
        } else {
            let n = ages.count - 1
            let perYear = (p50[n - 1] - p50[n]) / (ages[n] - ages[n - 1])
            age = ages[n] + (p50[n] - v) / perYear
        }
        return min(max(Int(age.rounded()), youngest), oldest)
    }

    /// At or above the median woman in her 20s: the chart's youngest age.
    public static func isTopOfChart(vo2Max: Double) -> Bool { vo2Max >= p50[0] }

    /// Fitness ages for her estimate give or take a typical Watch error,
    /// youngest first.
    public static func range(vo2Max: Double) -> ClosedRange<Int> {
        estimate(vo2Max: vo2Max + watchError)...estimate(vo2Max: vo2Max - watchError)
    }

    /// The range as shown: "31–44", "Under 34" when the young end reaches
    /// the chart's youngest age, "Under 25" when all of it does.
    public static func rangeText(vo2Max: Double) -> String {
        let r = range(vo2Max: vo2Max)
        if r.upperBound <= youngest { return "Under \(youngest)" }
        if r.lowerBound <= youngest { return "Under \(r.upperBound)" }
        return "\(r.lowerBound)\u{2013}\(r.upperBound)"
    }

    /// The age group she's compared with: her decade, the 20s for anyone
    /// younger (the norms start at 20), the 70s for anyone older.
    public static func decade(age: Int) -> Int { min(max(age / 10 * 10, 20), 70) }

    /// Plain level against women in her decade: below the 25th percentile
    /// "Below average", above the 75th "Above average", the middle half
    /// "About average". Each band is wider than a Watch's usual error, so
    /// it doesn't flip from one estimate to the next. Under-20s are
    /// "compared with women in their 20s".
    public static func level(vo2Max: Double, age: Int) -> String {
        let d = decade(age: age)
        let i = (d - 20) / 10
        let band: String
        if vo2Max < p25[i] { band = "Below average" }
        else if vo2Max > p75[i] { band = "Above average" }
        else { band = "About average" }
        return band + (age < 20 ? " compared with women in their 20s" : " for women in their \(d)s")
    }
}

// MARK: - What-if comparisons from her own nights

/// Compares nights with and without a factor (drinks, late caffeine…).
public struct HabitEffect: Hashable, Sendable {
    public var withCount: Int
    public var withoutCount: Int
    public var asleepDelta: Int
    public var hrvDeltaPct: Double?
    public var restingHRDelta: Double?
    public var checkInDelta: Double?

    /// Nights needed on each side before a comparison means anything.
    public static let minimumNights = 5
    public var enoughData: Bool { withCount >= Self.minimumNights && withoutCount >= Self.minimumNights }

    public static func compare(_ nights: [NightRecord], where test: (NightRecord) -> Bool) -> HabitEffect {
        let a = nights.filter(test), b = nights.filter { !test($0) }
        func diff(_ key: KeyPath<NextDayOutcome, Double?>) -> Double? {
            guard let x = a.compactMap({ $0.outcome[keyPath: key] }).mean, let y = b.compactMap({ $0.outcome[keyPath: key] }).mean else { return nil }
            return x - y
        }
        let asleep = (a.map { Double($0.asleepMinutes) }.mean ?? 0) - (b.map { Double($0.asleepMinutes) }.mean ?? 0)
        return HabitEffect(withCount: a.count, withoutCount: b.count, asleepDelta: Int(asleep.rounded()),
                           hrvDeltaPct: diff(\.hrvDeltaPct), restingHRDelta: diff(\.restingHRDelta), checkInDelta: diff(\.checkIn))
    }

    /// Like `compare`, but only compares nights within the same group (e.g.
    /// alarm mornings with alarm mornings, free with free), so a habit that
    /// mostly happens on weekends isn't credited with the weekend's longer
    /// sleep. Each group's difference is weighted by its smaller side; groups
    /// without nights on both sides are left out. Counts are the nights used.
    public static func compare<Key: Hashable>(_ nights: [NightRecord], where test: (NightRecord) -> Bool,
                                              within group: (NightRecord) -> Key) -> HabitEffect {
        let groups = Dictionary(grouping: nights, by: group)
        var parts: [(HabitEffect, Double)] = []
        for (_, ns) in groups {
            let e = compare(ns, where: test)
            guard e.withCount > 0, e.withoutCount > 0 else { continue }
            parts.append((e, Double(min(e.withCount, e.withoutCount))))
        }
        guard !parts.isEmpty else { return HabitEffect(withCount: 0, withoutCount: 0, asleepDelta: 0) }
        func weighted(_ f: (HabitEffect) -> Double?) -> Double? {
            let xs = parts.compactMap { p in f(p.0).map { ($0, p.1) } }
            let w = xs.map(\.1).reduce(0, +)
            return w > 0 ? xs.map { $0.0 * $0.1 }.reduce(0, +) / w : nil
        }
        return HabitEffect(withCount: parts.map(\.0.withCount).reduce(0, +),
                           withoutCount: parts.map(\.0.withoutCount).reduce(0, +),
                           asleepDelta: Int((weighted { Double($0.asleepDelta) } ?? 0).rounded()),
                           hrvDeltaPct: weighted(\.hrvDeltaPct), restingHRDelta: weighted(\.restingHRDelta),
                           checkInDelta: weighted(\.checkInDelta))
    }
}

/// The caffeine cutoff experiment: hours asleep grouped by last-caffeine time.
/// `lastCaffeine` is minutes relative to midnight of the day the drink was
/// had (the app day), so a 12:30am drink is 1470 and counts as late.
public struct CaffeineCutoffTest: Hashable, Sendable {
    public struct Group: Hashable, Sendable { public var label: String; public var averageAsleep: Int; public var nights: Int }
    public var groups: [Group]
    public var nightsLogged: Int
    public var target: Int

    public static func make(lastCaffeineByNight: [(lastCaffeine: Minutes?, asleep: Int)], target: Int = 21) -> CaffeineCutoffTest {
        let buckets: [(String, (Minutes?) -> Bool)] = [
            ("No caffeine", { $0 == nil }),
            ("Before 12pm", { $0.map { $0 < 720 } ?? false }),
            ("12–3pm", { $0.map { $0 >= 720 && $0 < 900 } ?? false }),
            ("After 3pm", { $0.map { $0 >= 900 } ?? false }),
        ]
        let groups = buckets.compactMap { label, test -> Group? in
            let xs = lastCaffeineByNight.filter { test($0.lastCaffeine) }.map { Double($0.asleep) }
            guard let m = xs.mean else { return nil }
            return Group(label: label, averageAsleep: Int(m.rounded()), nights: xs.count)
        }
        return CaffeineCutoffTest(groups: groups, nightsLogged: lastCaffeineByNight.count, target: target)
    }
}

// MARK: - Pairing logs with nights

/// Which logged times belong to which night. A night is named by its wake day.
public enum NightPairing {
    /// The app day rolls over at 4:00am: until then it's still "last night".
    public static let dayStartMinutes = 240

    /// The drinking evening before a night: 5:00pm the day before the wake
    /// day until 5:00am on the wake day. Each time falls in exactly one night.
    public static func alcoholWindow(wakeDay: Date, calendar: Calendar = .current) -> DateInterval {
        DateInterval(start: Clock.date(17 * 60 - 1440, relativeTo: wakeDay, calendar: calendar),
                     end: Clock.date(5 * 60, relativeTo: wakeDay, calendar: calendar))
    }

    /// The last caffeine before the sleep that follows it: drinks from 4:00am
    /// of the day before the wake day up to sleep onset. Returns minutes
    /// relative to midnight of that day (after-midnight drinks are 1440+),
    /// or nil when none of `drinks` fall in that window.
    public static func lastCaffeine(drinks: [Date], wakeDay: Date, sleepOnset: Minutes, calendar: Calendar = .current) -> Minutes? {
        let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: wakeDay)) ?? wakeDay
        let start = Clock.date(dayStartMinutes, relativeTo: day, calendar: calendar)
        let onset = Clock.date(sleepOnset, relativeTo: wakeDay, calendar: calendar)
        return drinks.filter { $0 >= start && $0 < onset }.map { Clock.minutes($0, relativeTo: day, calendar: calendar) }.max()
    }
}

// MARK: - Late nights

public enum LateNights {
    /// How much later than her usual (median) bedtime counts as a late night.
    public static let marginMinutes = 90
    /// Bedtimes from at least this many nights set her usual; with fewer, 2am.
    public static let minimumNights = 7

    /// Bedtimes (minutes relative to the wake day) at or after this are late.
    public static func threshold(bedtimes: [Minutes]) -> Minutes {
        guard bedtimes.count >= minimumNights, let m = bedtimes.map(Double.init).median else { return 120 }
        return Int(m.rounded()) + marginMinutes
    }
}

// MARK: - Streaks

public enum Streaks {
    /// Consecutive most-recent entries (newest first) passing the test.
    /// Not calendar-aware: prefer `current(days:matching:today:todayPending:)`.
    public static func current(_ newestFirst: [Bool]) -> Int { newestFirst.prefix { $0 }.count }
    public static func longest(_ values: [Bool]) -> Int {
        var best = 0, run = 0
        for v in values { run = v ? run + 1 : 0; best = max(best, run) }
        return best
    }

    /// Calendar-aware current streak. `days` are the days with a record (a
    /// tracked night, a check-in…), `matching` the ones that met the goal.
    /// Counts back one calendar day at a time from `today`; a day with no
    /// record or that missed the goal ends the streak. When `todayPending`
    /// (today can still happen, like a check-in not done yet) and today
    /// doesn't count yet, the streak runs through yesterday instead of
    /// reading 0.
    public static func current(days: [Date], matching: Set<Date>, today: Date, todayPending: Bool, calendar: Calendar = .current) -> Int {
        let hits = Set(days.map { calendar.startOfDay(for: $0) }).intersection(matching.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: today)
        if !hits.contains(day) {
            guard todayPending, let y = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var n = 0
        while hits.contains(day) {
            n += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    /// Calendar-aware longest run of consecutive days in `matching`.
    public static func longest(matching: Set<Date>, calendar: Calendar = .current) -> Int {
        let sorted = Set(matching.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for d in sorted {
            if let p = previous, calendar.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = d
        }
        return best
    }
}
