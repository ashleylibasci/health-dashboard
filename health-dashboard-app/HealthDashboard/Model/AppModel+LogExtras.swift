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
    var bedtimeTonight: Minutes { 1440 + store.data.bedtime }

    /// Dose-aware: today's drinks, at their real sizes and times, leave 25 mg
    /// or more in your body at bedtime.
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

    /// Her cutoff for a typical drink falls before she's even up (9-hour
    /// half-life on the combined pill, ring or patch: 6:00am for a 12:30am
    /// bedtime). Screens must not print `caffeineCutoff` as a time then;
    /// use `caffeineCutoffShown` and the "one small drink early" copy.
    var caffeineCutoffBeforeWake: Bool { caffeineCutoff <= caffeineWakeTime }

    /// The cutoff to print, or nil when it falls before she's up.
    var caffeineCutoffShown: Minutes? { caffeineCutoffBeforeWake ? nil : caffeineCutoff }

    /// The biggest drink (mg, in 5s) she could have at her wake time and
    /// still be under 25 mg at bedtime. With a 9-hour half-life and a
    /// 12:30am bedtime that's about 85 mg at 7:30am.
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
        if mg < 25 { return "A small amount, under the 25 mg you want at bedtime." }
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
        let end = 1440 + store.data.bedtime - 60
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

    /// Drinks logged the evening before `night`: 5pm the day before to 5am
    /// that morning, the same window `followedDrinks` uses.
    func alcoholEntries(before night: NightRecord) -> [AppData.AlcoholEntry] {
        let window = NightPairing.alcoholWindow(wakeDay: night.wakeDay)
        return store.data.alcoholLog.filter { window.contains($0.date) }
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
            let text: String? = entries.isEmpty ? nil : entries.map { $0.count > 1 ? "\($0.kind) ×\($0.count)" : $0.kind }.joined(separator: ", ")
            return DrinkNightPoint(index: i, night: night, asleep: asleep, afterDrinks: after, drinksText: text)
        }
    }
}
