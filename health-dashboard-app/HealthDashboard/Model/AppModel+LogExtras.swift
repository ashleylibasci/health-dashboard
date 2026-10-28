import Foundation
import HealthCore

/// One point on today's running water total.
struct WaterRunPoint: Identifiable, Hashable {
    var time: Minutes
    var ml: Double
    var id: Minutes { time }
}

/// One recent night for the drinks chart.
struct DrinkNightPoint: Identifiable, Hashable {
    var index: Int
    var night: NightRecord
    var asleep: Int
    var afterDrinks: Bool
    /// "Wine ×2, Shot" for the evening before, when logged in the app.
    var drinksText: String?
    var id: Int { index }
}

/// Values for the Log hub, Caffeine, Water, Drinks and cutoff-test screens.
extension AppModel {
    // MARK: Caffeine

    /// Caffeine in your body at `t` (minutes in the app day, may run past 1440),
    /// with her half-life (longer on the combined pill, ring or patch).
    func caffeineInBody(at t: Minutes) -> Double {
        CaffeineModel.amount(at: t, doses: caffeineDoses, halfLifeHours: caffeineHalfLifeHours)
    }

    /// Tonight's bedtime in app-day minutes (12:30am is 1470).
    var bedtimeTonight: Minutes { 1440 + tonightBedtime }

    /// Dose-aware: today's drinks, at their real sizes and times, leave
    /// `CaffeineModel.bedtimeLimitMg` or more in your body at bedtime.
    var caffeineTooMuchAtBedtime: Bool {
        CaffeineModel.tooMuchAtBedtime(doses: caffeineDoses, bedtime: bedtimeTonight, halfLifeHours: caffeineHalfLifeHours)
    }

    /// Whether a drink of `mg` at `t` (app-day minutes) would leave too much at bedtime,
    /// on top of what's already been had today.
    func wouldBeTooMuchAtBedtime(mg: Int, at t: Minutes) -> Bool {
        CaffeineModel.wouldBeTooMuch(adding: CaffeineDose(time: t, mg: mg), to: caffeineDoses,
                                     bedtime: bedtimeTonight, halfLifeHours: caffeineHalfLifeHours)
    }

    /// The latest time today a drink of `mg` still clears enough by bedtime,
    /// given what's already been had. Nil when there is no such time left:
    /// what's been had uses the allowance, or the time has already gone by
    /// (it's never earlier than now, or than her wake time).
    func latestTimeForCaffeine(mg: Int) -> Minutes? {
        CaffeineModel.latestTime(forMg: mg, bedtime: bedtimeTonight, existing: caffeineDoses, halfLifeHours: caffeineHalfLifeHours,
                                 notBefore: max(now, lastNightIsFresh ? lastNight.wake : 0))
    }

    /// The wake time the caffeine cutoff is compared with: last night's wake
    /// when it was recorded, else her "up by" time.
    var caffeineWakeTime: Minutes { lastNightIsFresh ? lastNight.wake : store.data.upBy }

    /// Her cutoff for a typical drink falls before she's even up, or within
    /// half an hour of waking (possible on the combined pill, ring or patch
    /// with an early bedtime): "Cutoff 8:30am" after an 8:17am wake read as
    /// a typo (design review F24). The cutoff is rounded down to the half
    /// hour, so that's as close to "right when you wake" as it gets. Screens
    /// must not print `caffeineCutoff` as a time then; use
    /// `caffeineCutoffShown` and the "Early only" copy.
    var caffeineCutoffBeforeWake: Bool { caffeineCutoff < caffeineWakeTime + 30 }

    /// The cutoff to print, or nil when it falls before (or right at) waking.
    var caffeineCutoffShown: Minutes? { caffeineCutoffBeforeWake ? nil : caffeineCutoff }

    /// The biggest drink (mg, in 5s) she could have at her wake time and
    /// still be under `CaffeineModel.bedtimeLimitMg` at bedtime.
    var caffeineLargestDoseAtWake: Int {
        CaffeineModel.largestDose(at: caffeineWakeTime, bedtime: bedtimeTonight, halfLifeHours: caffeineHalfLifeHours)
    }

    /// Caffeine left at tonight's bedtime from one drink of `mg` at `t`
    /// (app-day minutes), on its own.
    func caffeineLeftAtBedtime(mg: Int, at t: Minutes) -> Int {
        Int(CaffeineModel.amount(at: bedtimeTonight, doses: [CaffeineDose(time: t, mg: mg)], halfLifeHours: caffeineHalfLifeHours).rounded())
    }

    /// Her half-life is the longer one (combined pill, ring, patch).
    var caffeineLastsLonger: Bool { caffeineHalfLifeHours > CaffeineModel.typicalHalfLifeHours }

    /// What an amount of caffeine in your body is like, in plain words.
    static func caffeineMeaning(mg: Double) -> String {
        let espresso = 64.0
        if mg < 5 { return "Practically none left in your body." }
        if mg < CaffeineModel.bedtimeLimitMg { return "A small amount, under the \(Int(CaffeineModel.bedtimeLimitMg)) mg you want at bedtime." }
        let shots = mg / espresso
        if shots < 0.75 { return "About half an espresso's worth still active." }
        if shots < 1.4 { return "About one espresso's worth still active." }
        if shots < 2.4 { return "About two espressos' worth still active." }
        return "About \(Int(shots.rounded())) espressos' worth still active. That's a lot to clear before bed."
    }

    // MARK: Water

    var waterBottlesToday: Double {
        store.data.bottleSizeML > 0 ? waterTodayML / store.data.bottleSizeML : 0
    }

    var waterGoalBottles: Double {
        store.data.bottleSizeML > 0 ? store.data.waterGoalML / store.data.bottleSizeML : 0
    }

    /// Minutes of a date in the app day (after midnight runs past 1440).
    func appDayMinutes(_ date: Date) -> Minutes { Clock.minutes(date, relativeTo: appDayStart) }

    /// Water you've had by `t` (minutes in the app day).
    func waterML(by t: Minutes) -> Double {
        todaysWater.filter { appDayMinutes($0.date) <= t }.map(\.ml).reduce(0, +)
    }

    /// Running total through today as a stepped line: flat between drinks,
    /// jumping up at each one. Starts at `start` and runs to `end`.
    func waterRun(from start: Minutes, to end: Minutes) -> [WaterRunPoint] {
        var points = [WaterRunPoint(time: start, ml: 0)]
        var total = 0.0
        for entry in todaysWater {
            let t = max(appDayMinutes(entry.date), start)
            points.append(WaterRunPoint(time: t, ml: total))
            total += entry.ml
            points.append(WaterRunPoint(time: t, ml: total))
        }
        points.append(WaterRunPoint(time: max(end, points.last?.time ?? end), ml: total))
        // Ids must be unique for the chart; nudge repeated times by a minute.
        var seen = Set<Minutes>()
        return points.map { p in
            var q = p
            while seen.contains(q.time) { q.time += 1 }
            seen.insert(q.time)
            return q
        }
    }

    /// Water a steady pace would have reached by `t`, from waking to an hour before bed.
    func waterPace(at t: Minutes) -> Double {
        let start = lastNight.wake
        let end = 1440 + tonightBedtime - 60
        guard end > start else { return store.data.waterGoalML }
        let f = min(max(Double(t - start) / Double(end - start), 0), 1)
        return store.data.waterGoalML * f
    }

    // MARK: Alcohol

    /// Alcohol logged in the last `days` days, newest first.
    func recentAlcohol(days: Int = 14) -> [AppData.AlcoholEntry] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return store.data.alcoholLog.filter { $0.date >= since }.sorted { $0.date > $1.date }
    }

    /// Standard drinks logged in the last 6 hours (an evening out, or an
    /// afternoon party). A red cup of wine counts as about 3.
    var alcoholRecentDrinks: Double {
        let since = Date.now.addingTimeInterval(-6 * 3600)
        return store.data.alcoholLog.filter { $0.date >= since && $0.date <= .now }.map(\.standardDrinks).reduce(0, +)
    }

    /// Standard drinks logged today (since the rollover).
    var alcoholDrinksToday: Double { AppData.today(store.data.alcoholLog, date: \.date).map(\.standardDrinks).reduce(0, +) }

    /// 4 or more standard drinks in one evening is binge drinking for women
    /// (NIAAA): screens show the calm alcohol-poisoning safety line.
    var showsAlcoholSafetyLine: Bool { alcoholRecentDrinks >= 4 }

    /// Drinks logged the evening before `night`: 5pm the day before to 5am
    /// that morning, the same window `followedDrinks` uses.
    func alcoholEntries(before night: NightRecord) -> [AppData.AlcoholEntry] {
        alcoholEntries(beforeWakeDay: night.wakeDay)
    }

    func alcoholEntries(beforeWakeDay day: Date) -> [AppData.AlcoholEntry] {
        let window = NightPairing.alcoholWindow(wakeDay: day)
        return store.data.alcoholLog.filter { window.contains($0.date) }
    }

    /// The morning after 4+ standard drinks: when last night's alcohol has
    /// likely cleared (about 2 hours a drink), while that's still ahead
    /// (D1). `-demoFuel` previews show it whatever the clock says.
    var morningAfterClear: (time: Date, drinks: Double)? {
        let entries = alcoholEntries(beforeWakeDay: appDayDate)
        let total = entries.map(\.standardDrinks).reduce(0, +)
        guard total >= AlcoholClearance.morningAfterDrinks,
              let clear = AlcoholClearance.clearTime(entries.map { ($0.date, $0.standardDrinks) }),
              clear > .now || DemoMode.fuel else { return nil }
        return (clear, total)
    }

    /// Standard drinks the evening before a night (by its wake day).
    func standardDrinks(beforeWakeDay day: Date) -> Double {
        alcoholEntries(beforeWakeDay: day).map(\.standardDrinks).reduce(0, +)
    }

    /// Nights after 1–2 standard drinks, and after 3 or more, each compared
    /// with nights without (D2: the dose matters for sleep and HRV). Nil on
    /// example data, whose nights carry no amounts.
    var alcoholEffectByAmount: (light: HabitEffect, heavy: HabitEffect)? {
        guard !usingSampleData else { return nil }
        let amounts = Dictionary(nights.map { ($0.wakeDay, standardDrinks(beforeWakeDay: $0.wakeDay)) }, uniquingKeysWith: max)
        func band(_ range: ClosedRange<Double>) -> HabitEffect {
            HabitEffect.compare(nights.filter { (amounts[$0.wakeDay] ?? 0) == 0 || range.contains(amounts[$0.wakeDay] ?? 0) }) {
                range.contains(amounts[$0.wakeDay] ?? 0)
            }
        }
        return (band(0.5...2.5), band(3...100))
    }

    /// The last `count` nights, oldest first, flagged when they followed drinks.
    /// Sample nights get the same adjustment `alcoholEffect` uses so the chart
    /// and the summary agree.
    func recentDrinkNights(_ count: Int = 14) -> [DrinkNightPoint] {
        let recent = nights.sorted { $0.wakeDay < $1.wakeDay }.suffix(count)
        return recent.enumerated().map { i, night in
            let after = followedDrinks(night)
            let entries = alcoholEntries(before: night)
            let asleep = after && usingSampleData ? night.asleepMinutes - 25 : night.asleepMinutes
            let text: String? = entries.isEmpty ? nil : entries.map(\.phrase).joined(separator: ", ")
            return DrinkNightPoint(index: i, night: night, asleep: asleep, afterDrinks: after, drinksText: text)
        }
    }
}
