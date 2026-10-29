import Foundation
import HealthCore

/// Heart readings against her own usual and her cycle: the cycle's own
/// shift in recovery, the shared "up"/"down" bands, method-dependent
/// wording, and the dials on Today (round 4 women's health review).
extension AppModel {

    // MARK: The cycle's own shift

    /// Today's expected shift from a natural cycle: luteal (resting heart
    /// rate up 1.5, HRV down 4%), period week (the reverse) or none. Always
    /// none on the pill, ring, patch, implant or shot, and when the phase
    /// can't be told.
    var cycleHeartShift: CycleHeartShift { CycleHeartShift.make(cycleDisplay, periodLength: periodLength) }

    /// The shift on a past morning, from the cycle it really fell in (known
    /// period starts), never by counting today's cycle day backwards. None
    /// unless today's view is a natural cycle.
    func cycleHeartShift(on date: Date) -> CycleHeartShift {
        let typical: Int
        switch cycleDisplay {
        case let .phases(_, length, _): typical = length
        case let .overdue(_, length): typical = length
        default: return .none
        }
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: date)
        let starts = allPeriodStarts
        guard let i = starts.lastIndex(where: { $0 <= day0 }) else { return .none }
        let day = (cal.dateComponents([.day], from: starts[i], to: day0).day ?? 0) + 1
        let length = i + 1 < starts.count ? (cal.dateComponents([.day], from: starts[i], to: starts[i + 1]).day ?? typical) : typical
        return CycleHeartShift.forDay(day, length: length, periodLength: periodLength)
    }

    /// One sentence on what today's recovery allowed for, or nil.
    var recoveryCycleNote: String? {
        switch cycleHeartShift {
        case .luteal: "Allowed for: in the second half of your cycle resting heart rate runs a little higher and HRV a little lower."
        case .period: "Allowed for: in your period week resting heart rate runs a little lower and HRV a little higher."
        // On the pill: her own break-week shift, when she has one (E2).
        case .none: recoveryPackNote
        }
    }

    // MARK: Method-dependent wording

    /// Her heart readings can follow a natural cycle: she isn't on a method
    /// that stops ovulation (pill, ring, patch, implant, shot).
    var heartFollowsCycle: Bool { !ovulationStopped }

    /// " or the second half of your cycle" with a natural cycle; nothing on a
    /// method that stops ovulation. Ends a list of causes.
    var heartCycleCause: String { heartFollowsCycle ? ", or the second half of your cycle" : "" }

    /// How her cycle (or her method) moves heart readings, for the ⓘ sheets.
    var heartCycleNote: String {
        guard let bc = store.birthControl, bc.ovulation == .stopped else {
            return "With a natural cycle, resting heart rate runs about 1 to 2 beats higher and HRV a little lower in the second half (after ovulation), and the reverse in your period week. When the app knows where you are in your cycle, your recovery allows for it."
        }
        if bc.hasBreakWeek {
            return "On the \(bc.rawValue.lowercased()) you don\u{2019}t ovulate, so your heart rate, HRV and temperature don\u{2019}t swing with your pack, break week included. Changes are about sleep, stress, drinks, training or getting sick."
        }
        return "On the \(bc.rawValue.lowercased()) you don\u{2019}t ovulate, so your heart rate, HRV and temperature don\u{2019}t follow a monthly cycle. Changes are about sleep, stress, drinks, training or getting sick."
    }

    var hrvExplanation: Explanation {
        let base = Topic.hrv.explanation
        return Explanation(id: base.id, title: base.title, meaning: base.meaning,
                           forYou: "Only compare HRV with your own usual, never with other people\u{2019}s. It dips after a short night, drinks, a hard workout and when you\u{2019}re getting sick. " + heartCycleNote,
                           howWeGotIt: "Your usual is the middle of your last 30 mornings. \u{201C}Below\u{201D} and \u{201C}above\u{201D} take into account how much yours normally moves day to day, so an ordinary wobble isn\u{2019}t called strain. On Today, the dial shows where this morning sits in your own range over the last 30 days.")
    }

    var restingHRExplanation: Explanation {
        let base = Topic.restingHR.explanation
        return Explanation(id: base.id, title: base.title, meaning: base.meaning,
                           forYou: "\(Int(HeartBands.restingHRUp)) or more beats above your usual counts as up, everywhere in the app. That can mean short sleep, stress, drinks or getting sick. " + heartCycleNote,
                           howWeGotIt: "Your usual is the middle of your last 30 days. On Today, the dial shows where today sits in your own range over those days.")
    }

    // MARK: Bands and dials

    /// Today's resting heart rate against her usual, with the one shared cutoff.
    var restingHRLevel: HeartBands.Level { HeartBands.restingHR(delta: restingHRDelta) }
    /// Today's HRV against her usual and her own day-to-day spread.
    var hrvLevel: HeartBands.Level { HeartBands.hrv(deltaPct: hrvDeltaPct, spreadPct: hrvSpreadPct) }

    /// What an HRV change (% vs her usual) means, on her own bands. One
    /// wording for Recovery and Body.
    func hrvMeaning(_ pct: Double) -> String {
        switch HeartBands.hrv(deltaPct: pct, spreadPct: hrvSpreadPct) {
        case .wellBelow: "Your body was under some strain: short sleep, stress, drinks or getting sick can all do this\(heartCycleCause)."
        case .below: "A little below. Normal day-to-day wobble."
        case .usual: "Normal for you."
        case .above: "Well recovered."
        }
    }

    /// What a resting heart rate change (bpm vs her usual) means, with the
    /// one shared cutoff.
    func restingHRMeaning(_ delta: Double) -> String {
        switch HeartBands.restingHR(delta: delta) {
        case .above, .wellBelow: "Up from your usual. Often short sleep, stress, alcohol or a bug coming on\(heartCycleCause)."
        case .below: "A sign of good recovery."
        case .usual: "Normal for you."
        }
    }

    /// Where today's HRV sits on the dial: her own usual range fills the
    /// middle, or 0–80 ms before there are 10 days of it.
    var hrvGaugeFraction: Double {
        hrvUsualRange.map { HeartBands.gaugeFraction(hrv, range: $0) } ?? hrv / 80
    }
    var restingHRGaugeFraction: Double {
        restingHRUsualRange.map { HeartBands.gaugeFraction(restingHR, range: $0) } ?? restingHR / 120
    }

    // MARK: Stress and training scaled to her

    /// An active hour for her (about 1 kcal per kg), else 60 kcal.
    var stressActiveKcal: Double { StressModel.activeKcal(bodyMassKg: bodyMassKg) }

    // MARK: How she says she feels

    /// Symptoms that mean she feels sick, whatever the Watch says.
    static let feelSickSymptoms: Set<String> = ["Fever", "Sore throat", "Cough"]

    /// Fever, sore throat or cough logged today, in log order.
    var loggedSickSymptoms: [String] {
        let today = store.data.symptomLog.last { Calendar.current.isDateInToday($0.date) }?.symptoms ?? []
        return today.filter { Self.feelSickSymptoms.contains($0) }
    }

    /// The sick check's user-facing count of signs, mid-sentence.
    var sickSignsPhrase: String {
        illness.confidence == .high ? "several signs" : "a couple of signs"
    }
}
