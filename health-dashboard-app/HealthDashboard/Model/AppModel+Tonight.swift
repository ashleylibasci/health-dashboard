import Foundation
import HealthCore

/// Tonight's plan, worded once. Today, Sleep, the sick check, "Why do I feel
/// off?", Settings and the Watch all quote these, so they always agree
/// (round 3, N3/U6/N15). The numbers come from HealthCore's `TonightPlan`.
extension AppModel {
    /// Minutes to fall asleep, the same as the wake planner's default.
    static let planLatency = 12

    var tonightPlan: TonightPlan {
        let bed = store.data.bedtime, up = store.data.upBy
        return TonightPlan(need: tonightNeed, bedtime: bed, upBy: up, latency: Self.planLatency,
                           clockShift: clockShiftTonight(bedtime: bed, deadline: up), plan: wakePlan())
    }

    /// "Bed by 12:30am, up 8:22am" (always with am/pm). Without a plan, the
    /// up-by time.
    var tonightBedUpLine: String {
        let p = tonightPlan
        return "Bed by \(Clock.format(p.bedtime)), up \(Clock.format(p.wake ?? p.upBy))"
    }

    /// "8h 25m": tonight's need.
    var tonightNeedText: String { Clock.duration(tonightPlan.need) }

    /// Whether tonight's plan falls short of tonight's need, and by how
    /// much, in one plain line: "About 7h 40m asleep, 45 min short of
    /// tonight's 8h 25m. Bed by 11:05pm covers it." Nil when it covers it.
    var tonightShortNote: String? {
        let p = tonightPlan
        guard !p.coversNeed else { return nil }
        var text: String
        if p.bedtimeTooLateForNeed {
            // One wake time per sentence, named, so it doesn't read as a
            // second plan next to the headline's best wake (round 3, N3).
            text = "Even staying in bed until \(Clock.format(p.upBy)), the latest you can get up, that\u{2019}s \(Clock.duration(p.timeInBedAllowed)) in bed: at most about \(Clock.duration(p.mostSleepAllowed)) asleep, \(Clock.duration(max(p.need - p.mostSleepAllowed, 0))) short of the \(Clock.duration(p.need)) you need tonight."
        } else {
            text = "About \(Clock.duration(p.expectedAsleep)) asleep, \(Clock.duration(p.shortfall)) short of tonight\u{2019}s \(Clock.duration(p.need))."
        }
        if let bed = p.bedtimeToCoverNeed {
            text += " Bed by \(Clock.format(bed)) covers it."
        }
        return text
    }

    /// The bedtime to aim for tonight: the one that covers tonight's need
    /// when the planned bedtime doesn't, else the planned bedtime.
    var tonightAimBedtime: Minutes { tonightPlan.bedtimeToCoverNeed ?? store.data.bedtime }

    /// "Aim for 8h 25m tonight: bed by 11:05pm." The same need and bedtime
    /// Today and Sleep show.
    var tonightAimSentence: String {
        "Aim for \(tonightNeedText) tonight: bed by \(Clock.format(tonightAimBedtime))."
    }

    /// The three wake times, each with its name, so 8:22, 8:25 and 8:30
    /// aren't three unexplained numbers.
    var wakeTimesExplained: String? {
        let p = tonightPlan
        guard let wake = p.wake, let w = p.alarmWindow else { return nil }
        let alarm = "The smart alarm listens from \(Clock.format(w.start)) and wakes you when you start stirring, by \(Clock.format(w.end)) at the latest."
        if p.plan?.endsCycle == false {
            return "No sleep cycle ends close enough before \(Clock.format(p.upBy)), the latest you said you can get up, so you sleep until then. " + alarm
        }
        return "Best wake \(Clock.format(wake)) is near the end of a sleep cycle, a few minutes before up by \(Clock.format(p.upBy)), the latest you said you can get up. " + alarm
    }

    /// How tonight's debt payback relates to the debt itself (Maya N15).
    /// "Adding 30 minutes a night pays back about 3h 30m of your 5h 00m in a
    /// week. Older short nights also drop out of the two-week count."
    var debtPaybackSentence: String {
        let debt = sleepDebt
        guard debt >= 15 else { return "You have little or no sleep debt right now." }
        let perNight = max(tonightPlan.payback, 15)
        let nights = Int((Double(debt) / Double(perNight)).rounded(.up))
        if nights <= 7 {
            return "Adding \(Clock.duration(perNight)) a night brings your \(Clock.duration(debt)) down over about \(nights) \(nights == 1 ? "night" : "nights")."
        }
        return "Adding \(Clock.duration(perNight)) a night brings your \(Clock.duration(debt)) down by about \(Clock.duration(perNight * 7)) over a week. Short nights older than two weeks also drop out of the count."
    }
}
