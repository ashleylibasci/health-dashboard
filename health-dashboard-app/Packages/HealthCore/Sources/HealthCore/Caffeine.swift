import Foundation

public struct Drink: Hashable, Codable, Sendable, Identifiable {
    public enum Icon: String, Codable, Sendable, CaseIterable { case latte, iced, tea, can, shot }
    public var id: UUID
    public var name: String
    public var sizeLabel: String?
    public var caffeineMg: Int
    public var icon: Icon
    public var isCustom: Bool

    public init(id: UUID = UUID(), name: String, sizeLabel: String? = nil, caffeineMg: Int, icon: Icon = .latte, isCustom: Bool = false) {
        self.id = id; self.name = name; self.sizeLabel = sizeLabel; self.caffeineMg = caffeineMg; self.icon = icon; self.isCustom = isCustom
    }

    /// Typical amounts. Coffee-shop brewed coffee is much stronger than
    /// home drip (a Starbucks tall is about 235 mg), and energy drinks and
    /// pre-workouts vary a lot (150 to 300 mg), so their labels win.
    public static let common: [Drink] = [
        Drink(name: "Latte", sizeLabel: "Double shot", caffeineMg: 130, icon: .latte),
        Drink(name: "Drip coffee", sizeLabel: "12 oz", caffeineMg: 140, icon: .latte),
        Drink(name: "Coffee-shop brewed", sizeLabel: "Tall, 12 oz", caffeineMg: 235, icon: .latte),
        Drink(name: "Espresso", sizeLabel: "Single", caffeineMg: 64, icon: .shot),
        Drink(name: "Black tea", sizeLabel: "8 oz", caffeineMg: 47, icon: .tea),
        Drink(name: "Matcha", sizeLabel: "1 tsp powder", caffeineMg: 70, icon: .tea),
        Drink(name: "Diet Coke", sizeLabel: "12 oz can", caffeineMg: 46, icon: .can),
        Drink(name: "Red Bull", sizeLabel: "8.4 oz can", caffeineMg: 80, icon: .can),
        Drink(name: "Energy drink", sizeLabel: "16 oz can", caffeineMg: 160, icon: .can),
        Drink(name: "Celsius or Alani Nu", sizeLabel: "12 oz can", caffeineMg: 200, icon: .can),
        Drink(name: "Pre-workout", sizeLabel: "1 scoop, check your label", caffeineMg: 200, icon: .shot),
    ]
}

/// Her caffeine, her sleep (E4): how long she took to fall asleep on
/// nights with more than `CaffeineModel.bedtimeLimitMg` still in her body
/// at bedtime, against the other nights. Caffeine clearance varies a lot
/// between people, and the pill slows it, so her own nights say more than
/// the average.
public struct CaffeineSleepComparison: Hashable, Sendable {
    public struct Night: Hashable, Sendable {
        public var caffeineAtBedtime: Double
        /// Bedtime to falling asleep.
        public var minutesToFallAsleep: Int
        public init(caffeineAtBedtime: Double, minutesToFallAsleep: Int) {
            self.caffeineAtBedtime = caffeineAtBedtime; self.minutesToFallAsleep = minutesToFallAsleep
        }
    }

    /// Logged nights before a result shows, and the fewest on each side.
    public static let nightsNeeded = 20
    public static let nightsPerSide = 5

    public var nights: Int
    /// Nights with more than the limit left at bedtime, and the rest.
    public var over: Int
    public var under: Int
    /// Average minutes to fall asleep, over-limit nights minus the rest.
    public var minutesLonger: Int?

    public var enoughData: Bool {
        nights >= Self.nightsNeeded && over >= Self.nightsPerSide && under >= Self.nightsPerSide
    }

    public static func make(_ nights: [Night], limit: Double = CaffeineModel.bedtimeLimitMg) -> CaffeineSleepComparison {
        let a = nights.filter { $0.caffeineAtBedtime > limit }.map { Double($0.minutesToFallAsleep) }
        let b = nights.filter { $0.caffeineAtBedtime <= limit }.map { Double($0.minutesToFallAsleep) }
        let delta: Int? = {
            guard !a.isEmpty, !b.isEmpty else { return nil }
            return Int((a.reduce(0, +) / Double(a.count) - b.reduce(0, +) / Double(b.count)).rounded())
        }()
        return CaffeineSleepComparison(nights: nights.count, over: a.count, under: b.count, minutesLonger: delta)
    }
}

public struct CaffeineDose: Hashable, Codable, Sendable {
    public var time: Minutes
    public var mg: Int
    public init(time: Minutes, mg: Int) { self.time = time; self.mg = mg }
}

/// Caffeine in the body over time: absorbed over ~45 minutes, then cleared
/// with a half-life of about 5 hours (it varies from roughly 3 to 7). The
/// combined pill slows clearance (estrogen slows the liver enzyme CYP1A2) to
/// about one and a half times as long, about 7.3 hours (one small study of
/// pill users: 7.9 vs 5.4 hours, 1.46 times, Abernethy & Todd 1985); the
/// ring and patch probably do the same. Every function takes the half-life so callers can
/// pass hers.
public enum CaffeineModel {
    public static let absorption = 45.0
    /// The usual half-life, without estrogen-containing birth control.
    public static let typicalHalfLifeHours = 5.0
    /// With the combined pill, ring or patch: about one and a half times as
    /// long (5 h × 7.9/5.4).
    public static let estrogenHalfLifeHours = 7.3
    /// More than this in a day is more than is generally fine for healthy
    /// adults (FDA, EFSA).
    public static let dailyGuideMg = 400
    /// The daily amount to stay under when you could be pregnant or are
    /// trying (ACOG), and the most in one go that's generally fine (EFSA).
    public static let lowerGuideMg = 200
    /// The caffeine left at bedtime that the app treats as worth a mention.
    /// A meta-analysis of sleep studies found a coffee (107 mg) needs about
    /// 8.8 hours before bed and a 217 mg pre-workout about 13.2 hours to
    /// avoid any measurable sleep loss (Gardiner et al. 2023); on this model
    /// both leave about 33–37 mg then. That is where the effect reaches
    /// zero, not where it starts to matter: 400 mg six hours before bed
    /// (about 180 mg left) cost about an hour (Drake et al. 2013). With the
    /// zero-effect line the pill's longer half-life flagged a 12 oz coffee
    /// on waking for anyone awake under 15 hours, so the line is 50 mg
    /// (Ashley, Oct 30, 2026; it was 25, then 35).
    public static let bedtimeLimitMg = 50.0

    /// A normal amount of caffeine (up to `lowerGuideMg`) in the first
    /// `morningHours` after she wakes is never flagged or shrunk, whatever
    /// her bedtime (Ashley, Oct 30, 2026). It still counts toward the mg
    /// shown at bedtime; it just never triggers a warning or a smaller
    /// suggestion.
    public static let morningHours = 3.0
    static var morningMinutes: Minutes { Minutes(morningHours * 60) }

    /// Whether `t` falls in the morning allowance after waking at `wake`.
    public static func isMorning(_ t: Minutes, wake: Minutes) -> Bool { t <= wake + morningMinutes }

    /// The morning allowance (mg) left after these doses.
    static func morningRoom(_ doses: [CaffeineDose], wake: Minutes?) -> Int {
        guard let wake else { return 0 }
        return max(0, lowerGuideMg - doses.filter { isMorning($0.time, wake: wake) }.map(\.mg).reduce(0, +))
    }

    /// Caffeine at bedtime that counts against `bedtimeLimitMg`: everything
    /// except the morning allowance (the first `lowerGuideMg` had within
    /// `morningHours` of `wake`). Without a wake time, all of it.
    public static func countedAtBedtime(doses: [CaffeineDose], bedtime: Minutes, halfLifeHours: Double = 5, wake: Minutes? = nil) -> Double {
        guard let wake else { return atBedtime(doses: doses, bedtime: bedtime, halfLifeHours: halfLifeHours) }
        var allowance = lowerGuideMg
        var counted: [CaffeineDose] = []
        for d in doses.sorted(by: { $0.time < $1.time }) {
            guard isMorning(d.time, wake: wake), allowance > 0 else { counted.append(d); continue }
            let free = min(d.mg, allowance)
            allowance -= free
            if d.mg > free { counted.append(CaffeineDose(time: d.time, mg: d.mg - free)) }
        }
        return atBedtime(doses: counted, bedtime: bedtime, halfLifeHours: halfLifeHours)
    }

    /// Absorption starts the moment a drink is logged (a few minutes' worth
    /// at once), so a drink just logged never reads as 0 mg.
    public static func amount(at t: Minutes, doses: [CaffeineDose], halfLifeHours: Double = 5) -> Double {
        doses.reduce(0) { total, d in
            let dt = Double(t - d.time)
            guard dt >= 0 else { return total }
            let absorbed = min(max(dt, 5) / absorption, 1)
            let elapsed = max(dt - absorption / 2, 0) / 60
            return total + Double(d.mg) * absorbed * pow(0.5, elapsed / halfLifeHours)
        }
    }

    /// Latest time for one drink of `mg` (100 by default) so under
    /// `bedtimeLimitMg` is left at bedtime, rounded down to the half hour.
    /// With `wake`, never before the end of the morning allowance for a
    /// normal drink (up to `lowerGuideMg`).
    public static func cutoff(bedtime: Minutes, halfLifeHours: Double = 5, mg: Double = 100, wake: Minutes? = nil) -> Minutes {
        let hours = halfLifeHours * log2(max(mg, bedtimeLimitMg) / bedtimeLimitMg) + 0.5
        var raw = bedtime - Int(hours * 60)
        if let wake, mg <= Double(lowerGuideMg) { raw = max(raw, wake + morningMinutes) }
        return raw - ((raw % 30) + 30) % 30
    }

    /// Caffeine left at `bedtime` from these doses.
    public static func atBedtime(doses: [CaffeineDose], bedtime: Minutes, halfLifeHours: Double = 5) -> Double {
        amount(at: bedtime, doses: doses, halfLifeHours: halfLifeHours)
    }

    /// Dose-aware: whether these doses (sizes and times as logged) leave
    /// `limitMg` or more in the body at bedtime, not counting the morning
    /// allowance when `wake` is given.
    public static func tooMuchAtBedtime(doses: [CaffeineDose], bedtime: Minutes, halfLifeHours: Double = 5, limitMg: Double = bedtimeLimitMg,
                                        wake: Minutes? = nil) -> Bool {
        countedAtBedtime(doses: doses, bedtime: bedtime, halfLifeHours: halfLifeHours, wake: wake) >= limitMg
    }

    /// Whether adding `dose` to what's already been had would leave `limitMg`
    /// or more at bedtime ("this energy drink now would be too much").
    public static func wouldBeTooMuch(adding dose: CaffeineDose, to doses: [CaffeineDose], bedtime: Minutes, halfLifeHours: Double = 5, limitMg: Double = bedtimeLimitMg,
                                      wake: Minutes? = nil) -> Bool {
        tooMuchAtBedtime(doses: doses + [dose], bedtime: bedtime, halfLifeHours: halfLifeHours, limitMg: limitMg, wake: wake)
    }

    /// The latest time (to the minute) a drink of `mg` can be had so that,
    /// together with what's already in the body at bedtime, under `limitMg`
    /// is left then. Nil when there is no such time: what's already been had
    /// uses the whole allowance, or the latest time is before `notBefore`
    /// (pass now, or the wake time when planning a day). Never a time that
    /// has already gone by. With `wake`, a drink that fits the morning
    /// allowance can always be had until the allowance ends.
    public static func latestTime(forMg mg: Int, bedtime: Minutes, existing doses: [CaffeineDose] = [], halfLifeHours: Double = 5,
                                  limitMg: Double = bedtimeLimitMg, notBefore: Minutes? = nil, wake: Minutes? = nil) -> Minutes? {
        let already = countedAtBedtime(doses: doses, bedtime: bedtime, halfLifeHours: halfLifeHours, wake: wake)
        let room = limitMg - already
        let morningEnd = wake.flatMap { mg <= morningRoom(doses, wake: $0) ? $0 + morningMinutes : nil }
        guard room > 0 else {
            if let morningEnd, notBefore.map({ morningEnd >= $0 }) ?? true { return morningEnd }
            return nil
        }
        var latest: Minutes
        if Double(mg) < room {
            latest = bedtime
        } else {
            // After absorption: mg · 0.5^((dt − absorption/2) / 60 / h) < room.
            let dt = absorption / 2 + 60 * halfLifeHours * log2(Double(mg) / room)
            latest = bedtime - Int(dt.rounded(.up))
        }
        if let morningEnd { latest = max(latest, morningEnd) }
        if let notBefore, latest < notBefore { return nil }
        return latest
    }

    /// The biggest drink (mg, rounded down to 5) that could be had at `t`
    /// and still leave under `limitMg` at bedtime, with what's already been
    /// had. 0 when nothing fits. With `wake`, in the morning it's at least
    /// what's left of the morning allowance.
    public static func largestDose(at t: Minutes, bedtime: Minutes, existing doses: [CaffeineDose] = [], halfLifeHours: Double = 5, limitMg: Double = bedtimeLimitMg,
                                   wake: Minutes? = nil) -> Int {
        let free = wake.map { isMorning(t, wake: $0) ? morningRoom(doses, wake: $0) : 0 } ?? 0
        let room = limitMg - countedAtBedtime(doses: doses, bedtime: bedtime, halfLifeHours: halfLifeHours, wake: wake)
        guard room > 0, bedtime > t else { return free - free % 5 }
        let perMg = amount(at: bedtime, doses: [CaffeineDose(time: t, mg: 1)], halfLifeHours: halfLifeHours)
        guard perMg > 0 else { return free - free % 5 }
        let mg = free + Int((room / perMg).rounded(.down)) - 1
        return max(0, mg - mg % 5)
    }

    public struct Timing: Hashable, Sendable {
        public var bestWindow: TimeRange
        public var cutoff: Minutes
        public var coffeeNapAt: Minutes?
        public var note: String
        /// The cutoff for a typical drink comes before her grogginess has
        /// cleared (or before she's even awake): there's no safe window for a
        /// typical drink, and `bestWindow` is empty. Screens must not print
        /// the cutoff as a clock time then.
        public var cutoffBeforeWindow: Bool = false
    }

    /// Best caffeine window is from the end of grogginess to the cutoff. A
    /// coffee nap fits only if the afternoon dip starts before the cutoff.
    public static func timing(energy: EnergyDay, cutoff: Minutes, firstDrinkAt: Minutes?) -> Timing {
        let groggyEnd = energy.zone(.grogginess)?.range.end ?? energy.curve.first?.time ?? 480
        // After a late wake grogginess can clear after the cutoff; the window
        // is then empty (start == end), never inverted.
        let window = TimeRange(groggyEnd, max(groggyEnd, cutoff))
        let dipStart = energy.zone(.afternoonDip)?.range.start
        let nap: Minutes? = dipStart.flatMap { $0 < cutoff ? $0 - 5 : nil }
        var note: String
        let noWindow = groggyEnd >= cutoff
        if noWindow {
            note = "Even a typical coffee right after you wake would leave some caffeine at bedtime. If you have one, keep it small and early; daylight and water help too."
        } else if let first = firstDrinkAt {
            note = first < groggyEnd
                ? "Your first caffeine came while you were still groggy. Waiting until \(Clock.format(groggyEnd)) helps it work better."
                : "Your \(Clock.format(first)) caffeine landed after your grogginess cleared, when it helps most."
        } else {
            note = "Have your first coffee or tea after \(Clock.format(groggyEnd)), once grogginess clears."
        }
        if let nap {
            note += " Your dip starts before your cutoff, so a coffee nap fits: a regular coffee at \(Clock.format(nap)), then 20 minutes' sleep."
        } else if let dipStart, !noWindow {
            note += " Your dip starts at \(Clock.format(dipStart)), after your cutoff, so skip the coffee nap. Daylight or a short break works better."
        }
        return Timing(bestWindow: window, cutoff: cutoff, coffeeNapAt: nap, note: note, cutoffBeforeWindow: noWindow)
    }
}
