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

public struct CaffeineDose: Hashable, Codable, Sendable {
    public var time: Minutes
    public var mg: Int
    public init(time: Minutes, mg: Int) { self.time = time; self.mg = mg }
}

/// Caffeine in the body over time: absorbed over ~45 minutes, then cleared
/// with a half-life of about 5 hours (it varies from roughly 3 to 7). The
/// combined pill slows clearance (estrogen slows the liver enzyme CYP1A2) to
/// about one and a half times as long, about 8 hours (one small study of pill
/// users: 7.9 vs 5.4 hours, Abernethy & Todd 1985); the ring and patch
/// probably do the same. Every function takes the half-life so callers can
/// pass hers.
public enum CaffeineModel {
    public static let absorption = 45.0
    /// The usual half-life, without estrogen-containing birth control.
    public static let typicalHalfLifeHours = 5.0
    /// With the combined pill, ring or patch: about one and a half times as long.
    public static let estrogenHalfLifeHours = 8.0
    /// More than this in a day is more than is generally fine for healthy
    /// adults (FDA, EFSA).
    public static let dailyGuideMg = 400
    /// The daily amount to stay under when you could be pregnant or are
    /// trying (ACOG), and the most in one go that's generally fine (EFSA).
    public static let lowerGuideMg = 200
    /// Under this much at bedtime barely affects sleep.
    public static let bedtimeLimitMg = 25.0

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

    /// Latest time for one drink of `mg` (100 by default) so under 25 mg is
    /// left at bedtime, rounded down to the half hour.
    public static func cutoff(bedtime: Minutes, halfLifeHours: Double = 5, mg: Double = 100) -> Minutes {
        let hours = halfLifeHours * log2(max(mg, 25) / 25.0) + 0.5
        let raw = bedtime - Int(hours * 60)
        return raw - ((raw % 30) + 30) % 30
    }

    /// Caffeine left at `bedtime` from these doses.
    public static func atBedtime(doses: [CaffeineDose], bedtime: Minutes, halfLifeHours: Double = 5) -> Double {
        amount(at: bedtime, doses: doses, halfLifeHours: halfLifeHours)
    }

    /// Dose-aware: whether these doses (sizes and times as logged) leave
    /// `limitMg` or more in the body at bedtime.
    public static func tooMuchAtBedtime(doses: [CaffeineDose], bedtime: Minutes, halfLifeHours: Double = 5, limitMg: Double = 25) -> Bool {
        atBedtime(doses: doses, bedtime: bedtime, halfLifeHours: halfLifeHours) >= limitMg
    }

    /// Whether adding `dose` to what's already been had would leave `limitMg`
    /// or more at bedtime ("this energy drink now would be too much").
    public static func wouldBeTooMuch(adding dose: CaffeineDose, to doses: [CaffeineDose], bedtime: Minutes, halfLifeHours: Double = 5, limitMg: Double = 25) -> Bool {
        tooMuchAtBedtime(doses: doses + [dose], bedtime: bedtime, halfLifeHours: halfLifeHours, limitMg: limitMg)
    }

    /// The latest time (to the minute) a drink of `mg` can be had so that,
    /// together with what's already in the body at bedtime, under `limitMg`
    /// is left then. Nil when there is no such time: what's already been had
    /// uses the whole allowance, or the latest time is before `notBefore`
    /// (pass now, or the wake time when planning a day). Never a time that
    /// has already gone by.
    public static func latestTime(forMg mg: Int, bedtime: Minutes, existing doses: [CaffeineDose] = [], halfLifeHours: Double = 5,
                                  limitMg: Double = 25, notBefore: Minutes? = nil) -> Minutes? {
        let already = atBedtime(doses: doses, bedtime: bedtime, halfLifeHours: halfLifeHours)
        let room = limitMg - already
        guard room > 0 else { return nil }
        let latest: Minutes
        if Double(mg) < room {
            latest = bedtime
        } else {
            // After absorption: mg · 0.5^((dt − absorption/2) / 60 / h) < room.
            let dt = absorption / 2 + 60 * halfLifeHours * log2(Double(mg) / room)
            latest = bedtime - Int(dt.rounded(.up))
        }
        if let notBefore, latest < notBefore { return nil }
        return latest
    }

    /// The biggest drink (mg, rounded down to 5) that could be had at `t`
    /// and still leave under `limitMg` at bedtime, with what's already been
    /// had. 0 when nothing fits.
    public static func largestDose(at t: Minutes, bedtime: Minutes, existing doses: [CaffeineDose] = [], halfLifeHours: Double = 5, limitMg: Double = 25) -> Int {
        let room = limitMg - atBedtime(doses: doses, bedtime: bedtime, halfLifeHours: halfLifeHours)
        guard room > 0, bedtime > t else { return 0 }
        let perMg = amount(at: bedtime, doses: [CaffeineDose(time: t, mg: 1)], halfLifeHours: halfLifeHours)
        guard perMg > 0 else { return 0 }
        let mg = Int((room / perMg).rounded(.down)) - 1
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
