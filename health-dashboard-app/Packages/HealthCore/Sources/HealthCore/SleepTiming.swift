import Foundation

// MARK: - Best bedtime and wake time

/// Her best bedtime and wake time (Dr. Park's method, Oct 28, 2026).
///
/// The answer is a 30-minute bedtime window whose end is "bed by". It starts
/// from what the app already knows (sleep need, up-by, body clock, time to
/// fall asleep): that is the prior, and it is all she sees until there are
/// 28 usable school nights. Her own nights can then only move the window
/// earlier, by 15, 30 or 45 minutes, never later than the bedtime that
/// covers her need, and never move the wake time.
///
/// Personal evidence, in order:
/// 1. Only alarm nights (free nights mix bedtime with sleeping in), without
///    drinks, exams, illness, a clock change or a birth-control change.
/// 2. Each next morning gets a score from HRV, resting heart rate, sleep
///    efficiency and the check-in, against her own spread.
/// 3. Sleep length (and the jolt of a bedtime far from the night before)
///    is taken out first, so "earlier is better" can't just mean "longer
///    is better".
/// 4. Three groups by sleep onset (earlier, middle, later), not a search
///    over many windows, which would find a "best" by luck.
/// 5. The best group has to beat the worst by half her spread and 2.4
///    standard errors (allowing for neighbouring days resembling each
///    other), in both the older and newer half of her nights, with HRV or
///    resting heart rate agreeing.
///
/// Most of the time the honest answer is "no clear difference, keep your
/// times regular", and the result says so. Design bars (28 and 56 nights,
/// 2.4 SE, ±30 minutes, the 0.7 correlation gate, the 45-minute cap, the
/// weights and the 30-point balance rule) are the method's own choices.
public enum SleepTiming {
    /// Eligible alarm nights before her own nights count at all (four weeks).
    public static let minimumNights = 28
    /// Eligible alarm nights for "Fairly sure" (eight weeks).
    public static let fairNights = 56
    public static let minGroupNights = 8
    public static let minGroupWeeks = 3
    /// The bedtime window is 30 minutes wide: a wearable's sleep onset is
    /// good to roughly 15 minutes either way.
    public static let windowWidth = 30
    public static let maxEarlierShift = 45
    public static let step = 15
    /// "Within 30 minutes of this" for the regularity count.
    public static let regularityTolerance = 30
    public static let regularityNights = 14
    /// Free nights may sit at most an hour later than school nights.
    public static let freeNightCap = 60
    /// Only the most recent nights count.
    public static let historyNights = 120
    /// Minutes to fall asleep when she has too few nights to measure it.
    public static let defaultLatency = 12

    /// What the app knows about a night besides the record itself.
    public struct Flags: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// An evening with drinks: lower HRV and higher resting heart rate
        /// overnight, and often a late bedtime.
        public static let alcohol = Flags(rawValue: 1)
        /// The two days before an exam and the exam day: stress lowers HRV
        /// and keeps people up, so "late" and "stressed" can't be told apart.
        public static let exam = Flags(rawValue: 2)
        /// Symptoms logged that day.
        public static let unwell = Flags(rawValue: 4)
        public static let clockChange = Flags(rawValue: 8)
        /// Pill break week (balance check only).
        public static let breakWeek = Flags(rawValue: 16)
        /// Luteal phase of a natural cycle (balance check only; HRV and
        /// resting heart rate are already adjusted for it).
        public static let luteal = Flags(rawValue: 32)
        /// Caffeine after 2pm (balance check only).
        public static let lateCaffeine = Flags(rawValue: 64)
        /// Before a birth-control change the app knows the date of.
        public static let beforeMethodChange = Flags(rawValue: 128)

        /// Nights left out of the comparison.
        public static let excluding: Flags = [.alcohol, .exam, .unwell, .clockChange, .beforeMethodChange]
    }

    /// One night with what the app knows about it.
    public struct Night: Hashable, Sendable {
        public var record: NightRecord
        public var flags: Flags
        /// `.none` on the pill and other methods that stop ovulation.
        public var cycleShift: CycleHeartShift
        /// A week number, for "spans at least 3 different weeks".
        public var wakeWeek: Int

        public init(record: NightRecord, flags: Flags = [], cycleShift: CycleHeartShift = .none, wakeWeek: Int) {
            self.record = record; self.flags = flags; self.cycleShift = cycleShift; self.wakeWeek = wakeWeek
        }
    }

    /// The same vocabulary as the sleep need's confidence.
    public enum Confidence: String, Hashable, Sendable { case learning, early, fair }

    /// What set the window.
    public enum Basis: String, Hashable, Sendable {
        /// Her need before up-by.
        case needOnly
        /// Her body clock, which is earlier than the need-based bedtime.
        case needAndClock
        /// Her own nights moved it earlier.
        case personal
    }

    /// The one extra line the result may carry.
    public enum Caveat: String, Hashable, Sendable, CaseIterable {
        /// Her later bedtimes are her shorter nights.
        case notSeparable
        /// Her bedtimes are too close together to compare.
        case tooSteady
        /// Her middle group did best: her usual time is working.
        case usualWorks
        /// Her later nights looked no worse at the same length.
        case laterNotWorse
        /// Gates passed, but no time of night clearly won.
        case inconclusive
        /// The best group has far more or fewer nights of one kind.
        case lutealImbalance, breakWeekImbalance, lateCaffeineImbalance

        public var text: String {
            switch self {
            case .notSeparable:
                "On school nights your later bedtimes are your shorter nights, so the app can't tell time of night from sleep length yet. Sleep length is what your data supports."
            case .tooSteady:
                "Your bedtimes are within about an hour of each other, so there's nothing to compare yet."
            case .usualWorks:
                "Your usual time of night is working: neither earlier nor later nights went clearly better."
            case .laterNotWorse:
                "Your later nights didn't look worse at the same sleep length, but going later still leaves less time to sleep before your alarm."
            case .inconclusive:
                "No time of night clearly worked better for you. Keeping it the same each night is the best bet."
            case .lutealImbalance:
                "Many of the nights behind this were in the same part of your cycle, so this could change."
            case .breakWeekImbalance:
                "Many of the nights behind this were in your pill break week, so this could change."
            case .lateCaffeineImbalance:
                "Late caffeine was more common on some of these nights than others, so this could change."
            }
        }
    }

    /// The finding behind a personal window.
    public struct Evidence: Hashable, Sendable {
        public enum Lead: String, Hashable, Sendable { case hrv, restingHR }
        public var lead: Lead
        /// Best group minus worst, at the same sleep length: % HRV, or bpm
        /// lower resting heart rate. Whole numbers.
        public var delta: Int
        public var bestNights: Int
        public var worstNights: Int
        /// Asleep by: the best group's latest onset, rounded up to 5 minutes.
        public var onsetEdge: Minutes
        /// The best group's onsets, earliest to latest.
        public var bestOnsets: TimeRange
        /// The morning check-in agreed (half her spread or more).
        public var feltBetter: Bool
    }

    public struct Result: Hashable, Sendable {
        /// The bedtime window; `bed.end` is "bed by".
        public var bed: TimeRange
        /// The smart alarm window for `bed.end`, rounded out to 5 minutes,
        /// never after up-by.
        public var wake: TimeRange
        public var basis: Basis
        public var confidence: Confidence
        /// Eligible alarm nights, and how many the personal part needs.
        public var nightsUsed: Int
        public var nightsNeeded: Int
        /// 0, −15, −30 or −45.
        public var shift: Int
        public var evidence: Evidence?
        /// One sentence: the finding or what the window is based on.
        public var why: String
        public var caveat: Caveat?
        /// Her body clock against her mornings, when it costs her.
        public var clockNote: String?
        /// Nights of the last 14 asleep within 30 minutes of the window's
        /// middle onset.
        public var regularityHits: Int
        public var regularityOf: Int
        /// Spread of her last 14 sleep onsets, in minutes (5 or more nights).
        public var onsetSD: Int?
        /// Minutes to fall asleep used for the window.
        public var latency: Int

        /// "An early pattern from 31 nights. It could change."
        public var confidenceText: String {
            switch confidence {
            case .fair: return "Fairly sure from \(nightsUsed) nights, and it held in both halves."
            case .early: return "An early pattern from \(nightsUsed) nights. It could change."
            case .learning:
                let base = basis == .needAndClock ? "Based on the sleep you need and your body clock." : "Based on the sleep you need."
                return nightsUsed < nightsNeeded ? base + " Learning from your own nights (\(nightsUsed) of \(nightsNeeded))." : base
            }
        }
    }

    public struct Input: Hashable, Sendable {
        public var nights: [Night]
        /// Her base sleep need (not tonight's total), so the window doesn't
        /// jitter from day to day.
        public var need: Int
        public var upBy: Minutes
        /// Used until 14 nights give her own median.
        public var latency: Int
        public var cycleLength: Int
        public var chronotype: Chronotype?
        public var freeNights: Int
        public var workNights: Int
        /// −60 the night the clocks fall back, +60 when they spring forward.
        public var clockShift: Int
        public var tomorrowIsFree: Bool
        /// The smart alarm's listening time before a cycle end.
        public var windowLength: Int

        public init(nights: [Night], need: Int, upBy: Minutes, latency: Int = SleepTiming.defaultLatency, cycleLength: Int = 92,
                    chronotype: Chronotype? = nil, freeNights: Int = 0, workNights: Int = 0, clockShift: Int = 0,
                    tomorrowIsFree: Bool = false, windowLength: Int = 22) {
            self.nights = nights; self.need = need; self.upBy = upBy; self.latency = latency; self.cycleLength = cycleLength
            self.chronotype = chronotype; self.freeNights = freeNights; self.workNights = workNights; self.clockShift = clockShift
            self.tomorrowIsFree = tomorrowIsFree; self.windowLength = windowLength
        }
    }

    // MARK: Recommend

    public static func recommend(_ i: Input) -> Result {
        let recent = Array(i.nights.sorted { $0.record.wakeDay < $1.record.wakeDay }.suffix(historyNights))

        // 1. The prior: the bedtime that covers her need, or her body
        //    clock's when that is earlier.
        let lat = medianLatency(recent) ?? i.latency
        let bedLate = roundDown5(i.upBy - i.need - lat - i.clockShift)
        var late = bedLate
        var basis = Basis.needOnly
        var clockNote: String?
        var msf: Minutes?
        if let c = i.chronotype, i.freeNights >= 4, i.workNights >= 8 {
            // Onset centred on her free-day mid-sleep, on the wake-day axis.
            let mid = aligned(c.midSleepFreeCorrected, near: bedLate + lat + i.need / 2)
            msf = mid
            let natural = roundDown5(mid - i.need / 2 - lat)
            if natural + step < bedLate {
                late = natural + step
                basis = .needAndClock
            }
            let gap = (mid - i.need / 2) - (late + lat)
            if gap > 45 {
                clockNote = "Your body clock runs later than your mornings, so this is a hard bedtime. Going to bed this early may take you longer to fall asleep."
                if gap > 120 {
                    clockNote! += " A body clock this much later than early classes is common at your age. Morning light and a steady wake time help."
                }
            }
        }

        // 2. Her own nights.
        let alarm = eligible(recent)
        var shift = 0
        var confidence = Confidence.learning
        var evidence: Evidence?
        var caveat: Caveat?
        if alarm.count >= minimumNights {
            let finding = compare(alarm, all: recent, need: i.need)
            switch finding {
            case .notSeparable: caveat = .notSeparable
            case .tooSteady: caveat = .tooSteady
            case .thinGroups: break
            case .usualWorks: caveat = .usualWorks
            case .laterNotWorse: caveat = .laterNotWorse
            case .inconclusive: caveat = .inconclusive
            case let .earlier(ev, medianOnset, fair, warning):
                confidence = fair ? .fair : .early
                let gap = Double(medianOnset - (late + lat))
                let scale = fair ? 1.0 : 0.5
                let raw = min(max(gap * scale, -Double(maxEarlierShift)), 0)
                shift = Int((raw / Double(step)).rounded()) * step
                if shift == 0 {
                    // The window already sits there: nothing to act on,
                    // so don't dress up the prior.
                    confidence = .learning
                } else {
                    evidence = ev
                    caveat = warning
                    basis = .personal
                }
            }
        }

        // 3. The window. Only ever earlier than the prior.
        late += shift
        var bed = TimeRange(late - windowWidth, late)
        if i.tomorrowIsFree {
            let jetlag = roundDown5(min(i.chronotype?.socialJetlag ?? 0, freeNightCap))
            bed = TimeRange(late + jetlag - windowWidth, late + jetlag)
        }

        // 4. Wake: the planner's smart alarm window for "bed by".
        let plan = WakePlanner.plan(.init(bedtime: late, latency: lat, cycleLength: i.cycleLength, deadline: i.upBy,
                                          tonightNeed: i.need, windowLength: i.windowLength, clockShift: i.clockShift))
        let wake = plan.map { TimeRange(roundDown5($0.alarmWindow.start), min(roundUp5($0.alarmWindow.end), i.upBy)) }
            ?? TimeRange(i.upBy - 25, i.upBy)

        // 5. Regularity over the last 14 nights, eligible or not.
        let last = recent.suffix(regularityNights).map(\.record.sleepOnset)
        let centre = late + lat - windowWidth / 2
        let hits = last.filter { abs(circularDifference($0, centre)) <= regularityTolerance }.count
        let sd = last.count >= 5 ? circularSD(last) : nil

        let why: String
        if let ev = evidence {
            why = sentence(for: ev)
        } else if basis == .needAndClock, let msf {
            why = "Your body clock's sleep is centred on about \(Clock.format(roundDown5(msf))); for \(Clock.duration(i.need)) of sleep that means bed by about \(Clock.format(late))."
        } else {
            why = "\(Clock.duration(i.need)) of sleep before your \(Clock.format(i.upBy)) up-by time means being in bed by \(Clock.format(late))."
        }

        return Result(bed: bed, wake: wake, basis: basis, confidence: confidence, nightsUsed: alarm.count,
                      nightsNeeded: minimumNights, shift: shift, evidence: evidence, why: why, caveat: caveat,
                      clockNote: clockNote, regularityHits: hits, regularityOf: last.count,
                      onsetSD: sd.map { Int($0.rounded()) }, latency: lat)
    }

    /// "Your HRV was 8% higher after nights you were asleep by 11:30pm, at
    /// the same sleep length." Never "because", "optimal" or "ideal".
    static func sentence(for ev: Evidence) -> String {
        let edge = Clock.format(ev.onsetEdge)
        let base: String = switch ev.lead {
        case .hrv: "Your HRV was \(ev.delta)% higher after nights you were asleep by \(edge), at the same sleep length"
        case .restingHR: "Your resting heart rate was \(ev.delta) bpm lower after nights you were asleep by \(edge), at the same sleep length"
        }
        return base + (ev.feltBetter ? ", and you felt a bit better." : ".")
    }

    // MARK: Which nights count

    /// The alarm nights the comparison uses, oldest first: no drinks, exams,
    /// illness, clock change or birth-control change, at least 4 hours
    /// asleep, and HRV or resting heart rate the next morning.
    public static func eligible(_ nights: [Night]) -> [Night] {
        nights.sorted { $0.record.wakeDay < $1.record.wakeDay }.suffix(historyNights).filter { n in
            n.record.alarmUsed && n.flags.isDisjoint(with: .excluding) && n.record.asleepMinutes >= 240
                && (n.record.outcome.hrvDeltaPct != nil || n.record.outcome.restingHRDelta != nil)
        }
    }

    /// One bar of the HRV-by-bedtime chart: eligible nights whose sleep
    /// onset fell in a 30-minute slot, with their average HRV against her
    /// usual (a natural cycle's own shift taken out).
    public struct Slot: Hashable, Sendable {
        public var start: Minutes
        public var nights: Int
        public var hrvPct: Double?
    }

    /// The eligible nights in 30-minute onset slots, earliest first.
    public static func slots(_ nights: [Night], width: Int = 30) -> [Slot] {
        let groups = Dictionary(grouping: eligible(nights)) { n -> Int in
            Int((Double(n.record.sleepOnset) / Double(width)).rounded(.down)) * width
        }
        return groups.keys.sorted().map { start in
            let xs = groups[start]!
            let hrv = xs.compactMap { n in n.record.outcome.hrvDeltaPct.map(n.cycleShift.adjust(hrvDeltaPct:)) }
            return Slot(start: start, nights: xs.count, hrvPct: hrv.mean)
        }
    }

    /// Her own median minutes to fall asleep, from 14 or more nights.
    static func medianLatency(_ nights: [Night]) -> Int? {
        guard nights.count >= 14 else { return nil }
        let xs = nights.map { Double(min(max($0.record.sleepOnset - $0.record.bedtime, 0), 60)) }
        return xs.median.map { Int($0.rounded()) }
    }

    // MARK: The comparison

    enum Finding: Hashable {
        case notSeparable, tooSteady, thinGroups, usualWorks, laterNotWorse, inconclusive
        /// The earlier group did best: its evidence, its median onset,
        /// whether it's "fairly sure", and a balance warning.
        case earlier(Evidence, medianOnset: Minutes, fair: Bool, warning: Caveat?)
    }

    /// Each morning's outcomes, oriented so higher is better.
    struct Metrics: Hashable {
        var hrv: Double?, rhr: Double?, eff: Double?, chk: Double?
    }

    static func metrics(_ n: Night) -> Metrics {
        let o = n.record.outcome
        let inBed = n.record.wake - n.record.bedtime
        return Metrics(hrv: o.hrvDeltaPct.map(n.cycleShift.adjust(hrvDeltaPct:)),
                       rhr: o.restingHRDelta.map { -n.cycleShift.adjust(restingHRDelta: $0) },
                       eff: inBed > 0 ? min(Double(n.record.asleepMinutes) / Double(inBed), 1) * 100 : nil,
                       chk: o.checkIn)
    }

    /// Weights and spread floors: HRV leads (it's what she asked about),
    /// efficiency and the check-in count least.
    static let weights = (hrv: 1.0, rhr: 0.75, eff: 0.5, chk: 0.5)
    static let floors = (hrv: 1.0, rhr: 0.5, eff: 2.0, chk: 0.25)

    /// The morning score: weighted z-scores against her own mean and spread.
    /// Nil with fewer than 2 metrics or neither HRV nor resting heart rate.
    static func composite(_ ms: [Metrics]) -> [Double?] {
        func scale(_ xs: [Double?], floor: Double) -> (Double, Double) {
            let v = xs.compactMap { $0 }
            return (v.mean ?? 0, max(v.standardDeviation ?? 0, floor))
        }
        let h = scale(ms.map(\.hrv), floor: floors.hrv), r = scale(ms.map(\.rhr), floor: floors.rhr)
        let e = scale(ms.map(\.eff), floor: floors.eff), c = scale(ms.map(\.chk), floor: floors.chk)
        return ms.map { m in
            guard m.hrv != nil || m.rhr != nil else { return nil }
            let parts: [(Double, Double)] = [
                m.hrv.map { (($0 - h.0) / h.1, weights.hrv) }, m.rhr.map { (($0 - r.0) / r.1, weights.rhr) },
                m.eff.map { (($0 - e.0) / e.1, weights.eff) }, m.chk.map { (($0 - c.0) / c.1, weights.chk) },
            ].compactMap { $0 }
            guard parts.count >= 2 else { return nil }
            return parts.map { $0.0 * $0.1 }.reduce(0, +) / parts.map(\.1).reduce(0, +)
        }
    }

    static func compare(_ alarm: [Night], all: [Night], need: Int) -> Finding {
        let n = alarm.count
        let ms = alarm.map(metrics)
        let shortfall = alarm.map { Double(max(need - $0.record.asleepMinutes, 0)) / 60 }
        let jolt = jolts(alarm, all: all)
        let onsets = alarm.map { Double($0.record.sleepOnset) }

        // Can time of night be told from sleep length?
        if let iqr = interquartileRange(onsets), iqr < 60 { return .tooSteady }
        if let rho = correlation(onsets, shortfall), abs(rho) >= 0.7 { return .notSeparable }

        let allowLength = n >= 20 && (shortfall.variance ?? 0) > 0.05
        // A night without a score sits at her mean (0).
        guard let r = removeLengthAndJolt(composite(ms), shortfall: shortfall, jolt: jolt, allowLength: allowLength)?
            .map({ $0 ?? 0 }) else { return .inconclusive }
        let hrv = removeLengthAndJolt(ms.map(\.hrv), shortfall: shortfall, jolt: jolt, allowLength: allowLength) ?? ms.map(\.hrv)
        let rhr = removeLengthAndJolt(ms.map(\.rhr), shortfall: shortfall, jolt: jolt, allowLength: allowLength) ?? ms.map(\.rhr)
        let chk = ms.map(\.chk)

        // Three groups by onset (ties by date).
        let groups = terciles(alarm)
        guard groups.allSatisfy({ g in
            g.count >= minGroupNights && Set(g.map { alarm[$0].wakeWeek }).count >= minGroupWeeks
        }) else { return .thinGroups }
        let means = groups.map { g in g.map { r[$0] }.mean ?? 0 }
        let bestIndex = means.indices.max { means[$0] < means[$1] }!
        let worstIndex = means.indices.min { means[$0] < means[$1] }!
        if bestIndex == 1 { return .usualWorks }
        let best = groups[bestIndex], worst = groups[worstIndex]

        let sd = max(r.standardDeviation ?? 0, 1e-9)
        let diff = means[bestIndex] - means[worstIndex]
        let rho = lag1(r, days: alarm.map(\.record.wakeDay))
        let se = sd * (1 / nEff(best.count, rho: rho) + 1 / nEff(worst.count, rho: rho)).squareRoot()
        let passes = diff >= 0.5 * sd && diff >= 2.4 * se
        let holds = splitHalfSameSign(r, best: best, worst: worst)

        let hrvZ = contrast(hrv, best, worst), rhrZ = contrast(rhr, best, worst), chkZ = contrast(chk, best, worst)
        let leads = [hrvZ, rhrZ].compactMap { $0 }
        let agree = leads.contains { $0 >= 0.5 } && !leads.contains { $0 <= -0.5 } && (chkZ ?? 0) > -0.5
        guard passes && holds && agree else { return .inconclusive }
        if bestIndex == 2 { return .laterNotWorse }

        // What to say: HRV when it moved 3% or more, else resting heart rate
        // when it moved 1 bpm or more. Neither: no claim.
        let hrvDelta = rawDifference(hrv, best, worst), rhrDelta = rawDifference(rhr, best, worst)
        let lead: (Evidence.Lead, Int)
        if let d = hrvDelta, d.rounded() >= 3 { lead = (.hrv, Int(d.rounded())) }
        else if let d = rhrDelta, d.rounded() >= 1 { lead = (.restingHR, Int(d.rounded())) }
        else { return .inconclusive }

        let bestOnsets = best.map { alarm[$0].record.sleepOnset }.sorted()
        let warning = balanceWarning(alarm, best: best)
        let agreeing = [hrvZ, rhrZ, chkZ].compactMap { $0 }.filter { $0 >= 0.5 }.count
        let fair = n >= fairNights && warning == nil && agreeing >= 2
        let ev = Evidence(lead: lead.0, delta: lead.1, bestNights: best.count, worstNights: worst.count,
                          onsetEdge: roundUp5(bestOnsets.last!), bestOnsets: TimeRange(bestOnsets.first!, bestOnsets.last!),
                          feltBetter: (chkZ ?? 0) >= 0.5)
        let median = bestOnsets.map(Double.init).median.map { Int($0.rounded()) } ?? bestOnsets[bestOnsets.count / 2]
        return .earlier(ev, medianOnset: median, fair: fair, warning: warning)
    }

    /// Hours her onset moved from the night before (capped at 3), 0 when
    /// there was no night before. A late night isn't blamed for the
    /// irregularity it caused: regularity is judged on its own.
    static func jolts(_ alarm: [Night], all: [Night]) -> [Double] {
        let cal = Calendar.current
        var onsetByDay: [Date: Minutes] = [:]
        for n in all { onsetByDay[cal.startOfDay(for: n.record.wakeDay)] = n.record.sleepOnset }
        return alarm.map { n in
            let day = cal.startOfDay(for: n.record.wakeDay)
            guard let before = cal.date(byAdding: .day, value: -1, to: day), let prev = onsetByDay[before] else { return 0 }
            return Double(min(abs(circularDifference(n.record.sleepOnset, prev)), 180)) / 60
        }
    }

    /// Takes sleep length and jolt out of a series by least squares (with
    /// an intercept). Each slope must make things worse (≤ 0); a term with
    /// the wrong sign is dropped and the rest refitted. Missing values stay
    /// missing. Nil when nothing is present.
    static func removeLengthAndJolt(_ y: [Double?], shortfall: [Double], jolt: [Double], allowLength: Bool) -> [Double?]? {
        let idx = y.indices.filter { y[$0] != nil }
        guard !idx.isEmpty else { return nil }
        var terms: [[Double]] = allowLength ? [shortfall, jolt] : [jolt]
        var slopes: [Double] = []
        while !terms.isEmpty {
            guard let fit = leastSquares(idx.map { y[$0]! }, terms.map { col in idx.map { col[$0] } }) else {
                terms.removeLast(); continue
            }
            if let worst = fit.indices.filter({ fit[$0] > 0 }).max(by: { fit[$0] < fit[$1] }) {
                terms.remove(at: worst)
                continue
            }
            slopes = fit
            break
        }
        return y.indices.map { i in
            y[i].map { v in v - zip(slopes, terms).map { $0 * $1[i] }.reduce(0, +) }
        }
    }

    /// Ordinary least squares with an intercept; returns the slopes.
    static func leastSquares(_ y: [Double], _ xs: [[Double]]) -> [Double]? {
        let k = xs.count + 1
        guard y.count > k else { return nil }
        let rows = y.indices.map { i in [1.0] + xs.map { $0[i] } }
        var a = (0..<k).map { r in (0..<k).map { c in rows.map { $0[r] * $0[c] }.reduce(0, +) } }
        var b = (0..<k).map { r in zip(rows, y).map { $0[r] * $1 }.reduce(0, +) }
        // Gaussian elimination with partial pivoting.
        for col in 0..<k {
            guard let p = (col..<k).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }), abs(a[p][col]) > 1e-9 else { return nil }
            a.swapAt(col, p); b.swapAt(col, p)
            for row in 0..<k where row != col {
                let f = a[row][col] / a[col][col]
                for c in col..<k { a[row][c] -= f * a[col][c] }
                b[row] -= f * b[col]
            }
        }
        return (1..<k).map { b[$0] / a[$0][$0] }
    }

    /// Indices of the earlier, middle and later thirds by sleep onset.
    static func terciles(_ nights: [Night]) -> [[Int]] {
        let order = nights.indices.sorted {
            (nights[$0].record.sleepOnset, nights[$0].record.wakeDay) < (nights[$1].record.sleepOnset, nights[$1].record.wakeDay)
        }
        let base = order.count / 3, extra = order.count % 3
        let sizes = [base, base + (extra >= 1 ? 1 : 0), base + (extra == 2 ? 1 : 0)]
        return [Array(order[0..<sizes[0]]), Array(order[sizes[0]..<sizes[0] + sizes[1]]), Array(order[(sizes[0] + sizes[1])...])]
    }

    /// Lag-1 autocorrelation over consecutive calendar days, clamped to
    /// 0…0.6 (baselines are 30-day rolling means, so neighbours resemble
    /// each other). 0 with fewer than 5 pairs.
    static func lag1(_ r: [Double], days: [Date]) -> Double {
        let cal = Calendar.current
        var a: [Double] = [], b: [Double] = []
        for i in r.indices.dropLast() where cal.dateComponents([.day], from: cal.startOfDay(for: days[i]), to: cal.startOfDay(for: days[i + 1])).day == 1 {
            a.append(r[i]); b.append(r[i + 1])
        }
        guard a.count >= 5, let rho = correlation(a, b) else { return 0 }
        return min(max(rho, 0), 0.6)
    }

    /// Effective sample size with day-to-day carry-over (Bartlett 1946).
    static func nEff(_ n: Int, rho: Double) -> Double { max(Double(n) * (1 - rho) / (1 + rho), 1) }

    /// The best group beat the worst in both the older and the newer half
    /// of her nights (3 or more nights of each in each half).
    static func splitHalfSameSign(_ r: [Double], best: [Int], worst: [Int]) -> Bool {
        let half = r.count / 2
        for range in [0..<half, half..<r.count] {
            let b = best.filter(range.contains).map { r[$0] }, w = worst.filter(range.contains).map { r[$0] }
            guard b.count >= 3, w.count >= 3, let mb = b.mean, let mw = w.mean, mb > mw else { return false }
        }
        return true
    }

    /// Best minus worst group, in units of the metric's own spread.
    static func contrast(_ xs: [Double?], _ best: [Int], _ worst: [Int]) -> Double? {
        guard let d = rawDifference(xs, best, worst), let sd = xs.compactMap({ $0 }).standardDeviation, sd > 0 else { return nil }
        return d / sd
    }

    static func rawDifference(_ xs: [Double?], _ best: [Int], _ worst: [Int]) -> Double? {
        guard let b = best.compactMap({ xs[$0] }).mean, let w = worst.compactMap({ xs[$0] }).mean else { return nil }
        return b - w
    }

    /// A kind of night 30 points more (or less) common in the best group
    /// than in the rest, with at least 5 such nights: the first one found.
    static func balanceWarning(_ alarm: [Night], best: [Int]) -> Caveat? {
        let inBest = Set(best)
        let rest = alarm.indices.filter { !inBest.contains($0) }
        for (flag, caveat) in [(Flags.luteal, Caveat.lutealImbalance), (.breakWeek, .breakWeekImbalance), (.lateCaffeine, .lateCaffeineImbalance)] {
            guard alarm.filter({ $0.flags.contains(flag) }).count >= 5, !rest.isEmpty else { continue }
            let a = Double(best.filter { alarm[$0].flags.contains(flag) }.count) / Double(best.count)
            let b = Double(rest.filter { alarm[$0].flags.contains(flag) }.count) / Double(rest.count)
            if abs(a - b) >= 0.3 { return caveat }
        }
        return nil
    }

    // MARK: Small helpers

    static func roundDown5(_ m: Minutes) -> Minutes { Int((Double(m) / 5).rounded(.down)) * 5 }
    static func roundUp5(_ m: Minutes) -> Minutes { Int((Double(m) / 5).rounded(.up)) * 5 }

    /// `a − b` on a 24-hour clock, in −720…720 (11:50pm and 12:20am are 30 apart).
    static func circularDifference(_ a: Minutes, _ b: Minutes) -> Int {
        var d = (a - b) % 1440
        if d > 720 { d -= 1440 }
        if d < -720 { d += 1440 }
        return d
    }

    /// A clock time (0…1439) moved by whole days to within 12 hours of `target`.
    static func aligned(_ m: Minutes, near target: Minutes) -> Minutes {
        target + circularDifference(m, target)
    }

    /// Circular standard deviation of clock times, in minutes.
    static func circularSD(_ xs: [Minutes]) -> Double {
        let angles = xs.map { Double($0) / 1440 * 2 * .pi }
        let s = angles.map(sin).reduce(0, +) / Double(xs.count), c = angles.map(cos).reduce(0, +) / Double(xs.count)
        let length = min(max((s * s + c * c).squareRoot(), 1e-12), 1)
        return (-2 * log(length)).squareRoot() * 1440 / (2 * .pi)
    }

    static func interquartileRange(_ xs: [Double]) -> Double? {
        guard xs.count >= 4 else { return nil }
        let s = xs.sorted()
        func q(_ p: Double) -> Double {
            let i = p * Double(s.count - 1), lo = Int(i.rounded(.down)), hi = Int(i.rounded(.up))
            return s[lo] + (s[hi] - s[lo]) * (i - Double(lo))
        }
        return q(0.75) - q(0.25)
    }

    static func correlation(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= 3, let ma = a.mean, let mb = b.mean else { return nil }
        let cov = zip(a, b).map { ($0 - ma) * ($1 - mb) }.reduce(0, +)
        let va = a.map { ($0 - ma) * ($0 - ma) }.reduce(0, +), vb = b.map { ($0 - mb) * ($0 - mb) }.reduce(0, +)
        guard va > 0, vb > 0 else { return nil }
        return cov / (va * vb).squareRoot()
    }
}

extension Array where Element == Double {
    /// Sample variance; nil under 2 values.
    var variance: Double? { standardDeviation.map { $0 * $0 } }
}
