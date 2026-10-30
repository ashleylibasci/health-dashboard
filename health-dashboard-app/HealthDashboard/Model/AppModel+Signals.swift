import Foundation
import HealthCore

/// Stress, sickness signals, fitness, drinks, late nights, streaks and
/// "why do I feel off?", all derived from data the model already holds.
extension AppModel {
    var baselineHRV: Double { hrvDeltaPct > -100 ? hrv / (1 + hrvDeltaPct / 100) : hrv }
    var baselineRestingHR: Double { restingHR - restingHRDelta }

    /// Daylight minutes for the current app day: until the rollover, the
    /// calendar day before (Apple Health counts calendar days). Example data
    /// uses its own number.
    var daylightThisAppDay: Int? {
        if usingSampleData { return daylightToday }
        return daylightByDay[appDayDate].map { Int($0) }
    }

    /// Today's stress. No resting heart rate baseline: no levels and no
    /// label ("no data"), never a made-up "High". HRV is compared with her
    /// daytime HRV baseline (not the overnight one recovery uses). Heart
    /// rate is compared with her own still-hour heart rate once there's
    /// enough of it, else with her resting heart rate. In the luteal phase
    /// of a natural cycle 2 bpm and 5% HRV are allowed for, and an active
    /// hour is scaled to her weight (round 4).
    var stressToday: StressDay {
        let example = usingSampleData && !heartIsReal
        let hrvBase = example ? SampleData.baselineHRV : (stressHRVBaseline ?? 0)
        var samples = stressSamples
        if example {
            // The example day runs 7am–10pm. Like real data, show only hours
            // that have happened, with hours before the example night's wake
            // counted as asleep (round 3: a 10pm bar at 9pm, a 7am bar while
            // she slept until 8:17).
            let nowHour = Calendar.current.component(.hour, from: .now)
            let wake = lastNight.wake % 1440
            samples = samples.filter { $0.hour <= nowHour }.map { s in
                var s = s
                s.asleep = s.asleep || s.hour * 60 + 30 <= wake
                return s
            }
        }
        return StressModel.day(samples, restingHR: restingHRBaselineKnown ? baselineRestingHR : 0, baselineHRV: hrvBase,
                               still: example ? nil : stressStillBaseline, luteal: inLutealPhase, activeKcal: stressActiveKcal)
    }

    /// The start of this hour or the last one when that hour was still
    /// (not active, asleep or cooling down) and its stress read "High":
    /// the Watch offers a one-minute breather then (F5). Never on example
    /// data.
    var stressHighNow: Date? {
        guard heartIsReal || !usingSampleData else { return nil }
        let cal = Calendar.current
        let nowHour = cal.component(.hour, from: .now)
        guard let latest = stressToday.hours.last(where: { $0.level != nil }), latest.hour >= nowHour - 1,
              let level = latest.level, StressModel.label(for: level) == .high else { return nil }
        return cal.date(bySettingHour: latest.hour, minute: 0, second: 0, of: .now)
    }

    /// She logged a 4 or 5 ("stressed" or more) today.
    var feltStressedToday: Bool { (stressLoggedToday ?? 0) >= 4 }

    /// No stress level can be given today: no resting heart rate baseline
    /// yet, or no readings while still.
    var stressHasNoData: Bool { stressToday.label == nil }

    /// Stress you logged yourself today (1 calm – 5 very stressed).
    var stressLoggedToday: Int? { AppData.today(store.data.moodLog, date: \.date).last?.stress }

    /// Luteal allowance only for a natural cycle known to be in its luteal
    /// phase (not past her usual length). When a natural cycle's phase can't
    /// be told (irregular, PCOS, overdue, due around now, a method that may
    /// keep ovulation), no allowance is applied: the app doesn't assume a
    /// phase it can't see. `cyclePhaseUnknown` is still set on the result so
    /// screens and alerts can say the cycle might be part of it.
    /// "Hard training" is relative to her own usual active energy and her
    /// weight. The cutoffs scale with how much her own resting heart rate
    /// and HRV move, and drop a little in the first week of a natural
    /// period, when resting heart rate runs low (round 4, Brandt F6).
    var illness: IllnessSignal {
        let display = cycleDisplay
        let luteal = trackedCyclePhase == .luteal && !display.isPastUsualLength
        var signal = IllnessSignal.evaluate(restingHRDelta: restingHRDelta, hrvDeltaPct: hrvDeltaPct,
                                            respiratoryRateDelta: respiratoryRateDelta, wristTempDelta: wristTempDelta,
                                            lutealPhase: luteal,
                                            hardTrainingYesterday: hardTrainingYesterday,
                                            cyclePhaseUnknown: false,
                                            periodDay: cycleHeartShift == .period,
                                            restingHRSpread: restingHRSpread, hrvSpreadPct: hrvSpreadPct)
        signal.cyclePhaseUnknown = display.cyclePhaseUnknown && !luteal
        return signal
    }

    /// A couple of signs or several: Body's sick check, Today's sick card and
    /// "Why do I feel off?" (which leads with it) all agree. On example data
    /// the Today card says it's an example; alerts still need real data.
    var sickCheckFlagged: Bool {
        hasHeartData && (illness.confidence == .medium || illness.confidence == .high)
    }

    /// Yesterday's active energy was at least 1.5× her usual and 5 kcal per
    /// kg of her weight (8 kcal per kg with little history).
    var hardTrainingYesterday: Bool {
        IllnessSignal.isHardTraining(yesterdayKcal: activeCaloriesYesterday, earlierDaysKcal: activeCaloriesEarlier, bodyMassKg: bodyMassKg)
    }

    /// Fitness age on the FRIEND women's medians, 25 at the youngest. Show
    /// `fitnessAgeText` (a range) on screen.
    var fitnessAge: Int? {
        guard let v = vo2Max else { return nil }
        return FitnessAge.estimate(vo2Max: v)
    }
    /// The fitness age as a range for a Watch's usual error: "31–44",
    /// "Under 34", "Under 25".
    var fitnessAgeText: String? {
        vo2Max.map { FitnessAge.rangeText(vo2Max: $0) }
    }
    /// "About average for women in their 20s": the middle half of women her
    /// decade (under-20s against the 20s). Nil until she adds her age:
    /// without it there is no age group to compare with (round 3, N8). Show
    /// `fitnessLevelShown` on screen.
    var fitnessLevel: String? {
        guard let age = store.data.ageYears else { return nil }
        return vo2Max.map { FitnessAge.level(vo2Max: $0, age: age) }
    }
    /// The level, or a prompt for what's missing to work it out.
    var fitnessLevelShown: String? {
        guard vo2Max != nil else { return nil }
        return fitnessLevel ?? "Add your age to compare"
    }

    var caloriesToday: Double { activeCalories + restingCalories }

    /// Nights that followed an evening with drinks: anything logged from 5pm
    /// the day before the wake day to 5am on it, so each drink belongs to
    /// exactly one night.
    func followedDrinks(_ night: NightRecord) -> Bool {
        let cal = Calendar.current
        if usingSampleData {
            let back = cal.dateComponents([.day], from: night.wakeDay, to: cal.startOfDay(for: .now)).day ?? -1
            return SampleData.drinkNightOffsets.contains(back)
        }
        let window = NightPairing.alcoholWindow(wakeDay: night.wakeDay)
        return store.data.alcoholLog.contains { window.contains($0.date) }
    }

    /// Your nights after drinks compared with nights without.
    var alcoholEffect: HabitEffect {
        var nights = self.nights
        if usingSampleData {
            // The sample nights don't carry drinks, so show the designs' effect on them.
            nights = nights.map { n in
                guard followedDrinks(n) else { return n }
                var m = n
                m.outcome.hrvDeltaPct = (m.outcome.hrvDeltaPct ?? 0) - 12
                m.outcome.restingHRDelta = (m.outcome.restingHRDelta ?? 0) + 6
                m.outcome.checkIn = max(1, (m.outcome.checkIn ?? 3) - 1)
                m.asleepMinutes -= 25
                return m
            }
        }
        return HabitEffect.compare(nights, where: followedDrinks)
    }

    /// Her usual bedtime: the median over the last 60 nights (minutes
    /// relative to the wake day). Nil with fewer than 7 nights.
    var usualBedtime: Minutes? {
        let recent = nights.sorted { $0.wakeDay > $1.wakeDay }.prefix(60).map { Double($0.bedtime) }
        guard recent.count >= LateNights.minimumNights else { return nil }
        return recent.median.map { Int($0.rounded()) }
    }

    /// A bedtime at or after this is a late night: 90 minutes past her usual
    /// bedtime (2am until there are 7 nights to learn it from).
    var lateBedtimeThreshold: Minutes {
        LateNights.threshold(bedtimes: nights.sorted { $0.wakeDay > $1.wakeDay }.prefix(60).map(\.bedtime))
    }
    func isLate(_ night: NightRecord) -> Bool { night.bedtime >= lateBedtimeThreshold }

    /// The nights the late threshold is learned from (the last 60).
    private var lateWindowNights: [NightRecord] { Array(nights.sorted { $0.wakeDay > $1.wakeDay }.prefix(60)) }

    /// Late nights compared with the rest, over the same 60 nights the
    /// threshold comes from, and only within alarm mornings and within free
    /// mornings: late nights fall mostly on weekends, when everyone sleeps
    /// longer, so a plain comparison would credit them with weekend sleep.
    var lateNightEffect: HabitEffect { HabitEffect.compare(lateWindowNights, where: isLate, within: \.alarmUsed) }
    var lateNights: [NightRecord] { nights.filter(isLate).sorted { $0.wakeDay > $1.wakeDay } }

    /// Each night paired with the last caffeine before it (from 4am the day
    /// before up to falling asleep). After-midnight drinks count as late
    /// (1440+). A night with no drink logged counts as "No caffeine" only if
    /// she logged something in the app that day (a drink, water, alcohol or
    /// how she felt): a day she didn't open the log at all tells us nothing.
    /// Her own nights only, also while the rest of the app shows example
    /// data: the "14 of 21 nights" counter and the badge are claims about
    /// her (round 3, N6).
    var cutoffTest: CaffeineCutoffTest {
        let cal = Calendar.current
        let drinks = store.data.drinkLog.map(\.date)
        guard !drinks.isEmpty else { return CaffeineCutoffTest.make(lastCaffeineByNight: []) }
        let logged = store.data.drinkLog.map(\.date) + store.data.waterLog.map(\.date)
            + store.data.alcoholLog.map(\.date) + store.data.moodLog.map(\.date)
        let activeDays = Set(logged.map { cal.startOfDay(for: AppDay.day(containing: $0)) })
        let pairs: [(lastCaffeine: Minutes?, asleep: Int)] = nights.filter(isRealNight).compactMap { n in
            let last = NightPairing.lastCaffeine(drinks: drinks, wakeDay: n.wakeDay, sleepOnset: n.sleepOnset)
            let day = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: n.wakeDay)) ?? n.wakeDay
            guard last != nil || activeDays.contains(day) else { return nil }
            return (last, n.asleepMinutes)
        }
        return CaffeineCutoffTest.make(lastCaffeineByNight: pairs)
    }

    struct StreakInfo: Identifiable, Hashable {
        var id: String { title }
        var title: String
        var current: Int
        var longest: Int
        var unit: String
    }

    /// Whether a night met her need, the one threshold used everywhere
    /// (within 15 minutes of it).
    func metNeed(_ night: NightRecord) -> Bool {
        SleepNeedEstimator.metNeed(asleep: night.asleepMinutes, need: sleepNeed.minutes)
    }

    /// Her own nights from Apple Health (none while it's all example data).
    var realNights: [NightRecord] { nights.filter(isRealNight) }

    /// Calendar-aware: a night with no record, or one that missed, ends a
    /// streak. Before this morning's night (or check-in) is in, streaks run
    /// through yesterday instead of reading 0. Real nights only: example
    /// nights never make a streak of hers (round 3, N6).
    var streaks: [StreakInfo] {
        let cal = Calendar.current
        let mine = realNights
        let days = mine.map { cal.startOfDay(for: $0.wakeDay) }
        let nightPending = !mine.contains { cal.isDateInToday($0.wakeDay) }
        let onTime = Set(mine.filter { $0.sleepOnset <= store.data.bedtime + 20 }.map { cal.startOfDay(for: $0.wakeDay) })
        let met = Set(mine.filter(metNeed).map { cal.startOfDay(for: $0.wakeDay) })
        let checkInDays = store.data.checkIns.map { cal.startOfDay(for: $0.date) }
        let checkInPending = !store.data.checkIns.contains { cal.isDateInToday($0.date) }
        return [
            StreakInfo(title: "In bed on time",
                       current: Streaks.current(days: days, matching: onTime, today: .now, todayPending: nightPending),
                       longest: Streaks.longest(matching: onTime), unit: "nights"),
            StreakInfo(title: "Met your sleep need",
                       current: Streaks.current(days: days, matching: met, today: .now, todayPending: nightPending),
                       longest: Streaks.longest(matching: met), unit: "nights"),
            StreakInfo(title: "Morning check-ins",
                       current: Streaks.current(days: checkInDays, matching: Set(checkInDays), today: .now, todayPending: checkInPending),
                       longest: Streaks.longest(matching: Set(checkInDays)), unit: "days"),
        ]
    }

    struct OffReason: Identifiable, Hashable {
        var id: String { title }
        var title: String
        var detail: String
        var weight: Int
        var topic: Topic?
    }

    /// Today looks harder than usual: recovery below her usual band ("Take it
    /// steady" or "Go easy"), the sick check, or she logged a stressful day.
    /// Today's "Why do I feel off?" row shows only then.
    var mayFeelOff: Bool {
        if sickCheckFlagged || feltStressedToday { return true }
        guard let score = recoveryShown else { return false }
        return [.steady, .easy].contains(recoveryLevel(for: score))
    }

    /// The likeliest reasons today feels harder than usual, biggest first.
    var whyOffReasons: [OffReason] {
        var out: [OffReason] = []
        if sleepDebt >= 60 {
            out.append(.init(title: "Sleep debt", detail: "You're \(Clock.duration(sleepDebt)) behind your need over the last two weeks.", weight: min(sleepDebt / 20, 10), topic: .sleepDebt))
        }
        if let late = lateNights.first, (Calendar.current.dateComponents([.day], from: late.wakeDay, to: .now).day ?? 9) <= 3 {
            let usual = usualBedtime.map { ", well after your usual \(Clock.format($0))" } ?? ""
            out.append(.init(title: "A late night recently", detail: "Bed at \(Clock.format(late.bedtime))\(usual). A late night can take a couple of days to recover from.", weight: 7, topic: .lateNight))
        }
        if isLateLuteal {
            out.append(.init(title: "Late in your cycle", detail: "A higher resting heart rate and lower HRV are normal now, so feeling a bit flat is too. If it\u{2019}s more than flat (hopeless, panicky, intense anger) and it gets in the way of classes or friends most months, it\u{2019}s worth tracking: PMDD affects about 2\u{2013}6% of women and is treatable.", weight: 5, topic: .luteal))
        }
        if sickCheckFlagged {
            out.append(.init(title: "Your body may be fighting something", detail: "Several signals are off at once.", weight: 8, topic: .illness))
        }
        // What she said comes first: the body-signal "stress" is heart rate
        // at rest, which caffeine, heat or a meal move too (round 4, Laurent F4).
        if feltStressedToday {
            out.append(.init(title: "You said today\u{2019}s been stressful", detail: "You logged \(stressLoggedToday ?? 4) of 5 for stress today.", weight: 6, topic: .stress))
        }
        if let s = stressToday.label, s == .raised || s == .high {
            out.append(.init(title: "Your heart was busy at rest", detail: "Your heart rate has been up while you were sitting still. Stress can do that, and so can caffeine, heat, a meal or getting sick\(heartCycleCause).", weight: 4, topic: .stress))
        }
        if caffeineTooMuchAtBedtime {
            out.append(.init(title: "Caffeine that will still be around at bedtime", detail: "What you've had today leaves \(caffeineAtBedtime) mg at bedtime. That can make sleep a little lighter, even if you fall asleep fine.", weight: 3, topic: .caffeineCutoff))
        }
        // Daylight for this app day (after midnight that's still yesterday's
        // count, not the new day's 0), and only once she's been up a while.
        if let light = daylightThisAppDay, light < 15, now >= lastNight.wake + 180 {
            out.append(.init(title: "Little daylight", detail: "\(light) min so far. Morning light helps you feel awake.", weight: 2, topic: .daylight))
        }
        // The sick check, when it fires, leads: it's the one reason that
        // changes what she should do today (rest, fluids, no hard training).
        return out.sorted {
            let a = $0.topic == .illness, b = $1.topic == .illness
            return a != b ? a : $0.weight > $1.weight
        }
    }
}
