import Foundation
import HealthCore

/// One goal for the coming week, from the week's lowest day.
struct WeekGoal: Hashable {
    var title: String
    var detail: String
}

extension AppModel {
    /// "Your week" as a story (D-P1), from the same seven days as the recap.
    var weekStory: WeekStory? { WeekStory.make(days: lastWeek, cutoff: caffeineCutoffShown) }

    /// Where the recap's week fell in her pill pack (D-P1). Nil off the
    /// combined pill or without a pack.
    var packWeek: PackWeek? {
        guard let pack = pillPack else { return nil }
        let days = lastWeek.map(\.date).sorted()
        return PackWeek.make(pack: pack, days: days, today: currentPillDay, taken: isPillTaken(on:))
    }

    /// The story comes out on Sunday from 5pm (the app day, so until the
    /// rollover), and stays marked new until she opens it.
    var weekStoryIsOut: Bool {
        if DemoMode.weekStoryOut { return true }
        let cal = Calendar.current
        return cal.component(.weekday, from: appDayDate) == 1 && now >= 17 * 60
    }

    /// This week's key, for "seen": the Sunday it came out.
    var weekStoryKey: String { appDayDate.formatted(.iso8601.year().month().day()) }

    /// Caffeine that day was more than the night could clear: after her
    /// cutoff, or (when the cutoff falls before she's up) more than one small
    /// early drink.
    func caffeineTooLate(_ d: DaySummary) -> Bool {
        if let cutoff = caffeineCutoffShown { return (d.lastCaffeine ?? 0) > cutoff }
        return d.caffeineMg > caffeineLargestDoseAtWake
    }

    /// One thing for this week, from the week's lowest day: an earlier
    /// bedtime, the caffeine cutoff, the smart alarm, her sleep need, or
    /// morning daylight. Shared by the recap and the story.
    func weekGoal(_ recap: WeekRecap, need: Int) -> WeekGoal {
        let w = recap.worst
        let cal = Calendar.current
        let night = (cal.date(byAdding: .day, value: -1, to: w.date) ?? w.date).formatted(.dateTime.weekday(.wide))
        let day = w.date.formatted(.dateTime.weekday(.wide))
        if w.bedtime >= lateBedtimeThreshold {
            let target = max(store.data.bedtime, ((w.bedtime - 60) / 30) * 30)
            return WeekGoal(title: "Keep \(night) bedtime before \(Clock.format(target))",
                            detail: "Last \(night) night it was \(Clock.format(w.bedtime)). In bed by \(Clock.format(target)), you get more of your sleep need before your alarm, and more of the deep sleep that comes early in the night.")
        }
        if let last = w.lastCaffeine, caffeineTooLate(w) {
            guard let cutoffTime = caffeineCutoffShown else {
                return WeekGoal(title: caffeineNoCutoffShort,
                                detail: "On \(day) you had \(w.caffeineMg) mg. " + caffeineEarlyOnlyText)
            }
            let cutoff = Clock.format(cutoffTime)
            return WeekGoal(title: "Last caffeine before \(cutoff)",
                            detail: "On \(day) your last drink was at \(Clock.format(last)). Caffeine after \(cutoff) is still in your system at bedtime and makes sleep lighter.")
        }
        if !w.wokeFromLightSleep {
            return WeekGoal(title: "Try the smart alarm on your Watch",
                            detail: "On \(day) you woke from deep sleep. The smart alarm wakes you when you start stirring in the 25 minutes before your latest wake time, which can feel a bit easier.")
        }
        if w.asleep < need - 30 {
            return WeekGoal(title: "Get \(Clock.duration(need)) on \(night) night",
                            detail: "Last \(night) night you slept \(Clock.duration(w.asleep)), \(Clock.duration(need - w.asleep)) short of your need.")
        }
        return WeekGoal(title: "20 minutes of daylight before noon",
                        detail: "Your days averaged \(recap.averageDaylight) min. Morning light is the strongest signal your body clock gets.")
    }
}
