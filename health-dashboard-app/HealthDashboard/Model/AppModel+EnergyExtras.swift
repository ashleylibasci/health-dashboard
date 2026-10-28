import Foundation
import HealthCore

/// Derived values for the energy screens' interactive charts, the clock-change
/// plan, late nights, "why do I feel off?" and achievements. Computed only.
extension AppModel {

    // MARK: Energy curve, point by point

    /// What a moment on the energy curve means and what to do then.
    struct EnergyMoment: Hashable {
        var time: Minutes
        var level: Int
        /// The zone it falls in, if any.
        var kind: EnergyDay.Zone.Kind?
        /// "Afternoon dip", "Climbing out of the dip"
        var title: String
        /// The readout's note, one or two lines: the zone's one-liner, or
        /// what to do between zones (the title already says where she is).
        /// Each zone's full meaning opens from its row on Energy, and all of
        /// it is in the Health guide ("Your energy through the day").
        var note: String
    }

    /// The curve point nearest to `t`.
    static func nearestPoint(_ t: Minutes, in e: EnergyDay) -> EnergyDay.Point? {
        e.curve.min { abs($0.time - t) < abs($1.time - t) }
    }

    /// The zone a time falls in. Wind-down and the sleep window win over the
    /// daytime zones when they overlap.
    static func zone(at t: Minutes, in e: EnergyDay) -> EnergyDay.Zone? {
        let order: [EnergyDay.Zone.Kind] = [.melatonin, .windDown, .grogginess, .morningPeak, .afternoonDip, .secondWind]
        for k in order {
            if let z = e.zone(k), z.range.contains(t) { return z }
        }
        return nil
    }

    func energyMoment(at t: Minutes, in e: EnergyDay) -> EnergyMoment {
        let point = Self.nearestPoint(t, in: e)
        let time = point?.time ?? t
        let level = Int((point?.level ?? 0).rounded())
        if let z = Self.zone(at: time, in: e) {
            let line = zoneOneLinerShown(z.kind)
            return EnergyMoment(time: time, level: level, kind: z.kind, title: Self.zoneTitle(z),
                                note: line.prefix(1).uppercased() + line.dropFirst())
        }
        let peak = e.zone(.morningPeak)?.range
        let dip = e.zone(.afternoonDip)?.range
        let wind = e.zone(.secondWind)?.range
        let down = e.zone(.windDown)?.range
        let mel = e.zone(.melatonin)?.range
        func moment(_ title: String, _ note: String) -> EnergyMoment {
            EnergyMoment(time: time, level: level, kind: nil, title: title, note: note)
        }
        if let mel, time > mel.end {
            return moment("Past your sleep window", "Keep the lights low and head to bed as soon as you can.")
        }
        if let down, time < down.start, let wind, time > wind.end {
            return moment("Evening", "Good for lighter work, friends or dinner. Start wrapping up anything intense.")
        }
        if let dip, let wind, time > dip.end, time < wind.start {
            return moment("Climbing out of the dip", "Ease back into work that needs some focus.")
        }
        if let peak, let dip, time > peak.end, time < dip.start {
            return moment("Coming off your peak", "Finish your focused work now and save easy tasks for the dip.")
        }
        if let peak, time < peak.start {
            return moment("Warming up", "Start on something that needs focus. It only gets easier from here.")
        }
        return moment("Steady stretch", "Use it for whatever's next on your list.")
    }

    /// Every note the curve readout can show on this day, one per moment
    /// kind, so the readout keeps the height of the longest (Weber A1).
    func energyMomentNotes(in e: EnergyDay) -> [String] {
        Array(Set(e.curve.map { energyMoment(at: $0.time, in: e).note }))
    }

    /// "Sleep window", "Morning peak", or "First peak" when that peak
    /// starts after noon (late wake). Names follow the clock, from HealthCore.
    static func zoneTitle(_ zone: EnergyDay.Zone) -> String {
        zone.title
    }

    /// The zone's one-liner, the curve readout's note inside the zone.
    static func zoneOneLiner(_ kind: EnergyDay.Zone.Kind) -> String {
        switch kind {
        case .grogginess: return "the foggy just-woke-up feeling. Skip big decisions; get daylight and water."
        case .morningPeak: return "your sharpest focus of the day. Save it for your hardest studying."
        case .afternoonDip: return "a natural energy drop, mostly from your body clock (a big lunch can add to it). Plan easy tasks or a walk."
        case .secondWind: return "your energy lifts again. Good for a workout or group study."
        case .windDown: return "your own sleep hormone starts rising (not about pills). Dim lights, screens down."
        case .melatonin: return "the hour before you usually fall asleep. Usually the easiest time to drift off."
        }
    }

    static func zoneTopic(_ kind: EnergyDay.Zone.Kind) -> Topic {
        switch kind {
        case .grogginess: return .grogginess
        case .morningPeak: return .morningPeak
        case .afternoonDip: return .afternoonDip
        case .secondWind: return .secondWind
        case .windDown: return .windDown
        case .melatonin: return .melatonin
        }
    }

    /// Energy bank level at a time today (wake to bedtime).
    func energyBank(at t: Minutes) -> Double {
        EnergyBank.level(atWake: energyBankAtWake, hoursAwake: Double(max(t - lastNight.wake, 0)) / 60)
    }

    // MARK: Clock change

    /// Her usual wake time by the clock, for the clock-change plan.
    var timeChangeWake: Minutes { wakePlan()?.wake ?? 502 }

    /// The saved clock-change choice. Old saves may hold the other option as
    /// a default, so it only counts once she has picked it on the screen.
    func timeChangeStrategy(explicitlyChosen: Bool) -> TimeChangePlanner.Strategy {
        guard explicitlyChosen, let s = TimeChangePlanner.Strategy(rawValue: store.data.timeChangeStrategy) else { return .keepClockTimes }
        return s
    }

    /// TimeChangePlanner's nights, with one guarantee: "keep your usual times"
    /// never has her up earlier than usual, on any night.
    func timeChangeNights(_ strategy: TimeChangePlanner.Strategy) -> [TimeChangePlanner.Night] {
        let wake = timeChangeWake
        let nights = TimeChangePlanner.plan(bedtime: store.data.bedtime, wake: wake, shiftMinutes: -60, strategy: strategy)
        guard strategy == .keepClockTimes else { return nights }
        return nights.map { n in
            var m = n
            m.wake = max(n.wake, wake)
            return m
        }
    }

    /// The calendar date of the plan night with this offset (0 = the Saturday
    /// night before the Sunday change).
    func timeChangeNightDate(offset: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset - 1, to: nextFallBack) ?? nextFallBack
    }

    // MARK: Late nights

    /// One recent night: bedtime and how the next day went.
    struct BedtimePoint: Identifiable, Hashable {
        var id: Date { day }
        /// The wake day (the morning after).
        var day: Date
        var bedtime: Minutes
        var asleep: Int
        var hrvDeltaPct: Double?
        var restingHRDelta: Double?
        var checkIn: Double?
        var energy: Double?
        var isLate: Bool
    }

    /// The last 30 nights, oldest first.
    var recentBedtimes: [BedtimePoint] {
        let recent = nights.sorted { $0.wakeDay > $1.wakeDay }.prefix(30)
        let threshold = lateBedtimeThreshold
        return recent.reversed().map { n in
            BedtimePoint(day: n.wakeDay, bedtime: n.bedtime, asleep: n.asleepMinutes,
                         hrvDeltaPct: n.outcome.hrvDeltaPct, restingHRDelta: n.outcome.restingHRDelta,
                         checkIn: n.outcome.checkIn, energy: n.outcome.energyScore, isLate: n.bedtime >= threshold)
        }
    }

    /// The second day after a late night (the morning after the next, normal
    /// night), compared with other days.
    var lateNightDayAfterEffect: HabitEffect {
        let cal = Calendar.current
        let lateDays = Set(lateNights.map { cal.startOfDay(for: $0.wakeDay) })
        let threshold = lateBedtimeThreshold
        return HabitEffect.compare(nights) { n in
            guard let prev = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: n.wakeDay)) else { return false }
            return lateDays.contains(prev) && n.bedtime < threshold
        }
    }

    /// Sleep lost on late nights before an alarm morning vs. a free morning,
    /// compared with your normal nights. nil when there are none of that kind.
    var lateNightSleepCost: (alarm: Int?, free: Int?) {
        let threshold = lateBedtimeThreshold
        let normal = nights.filter { $0.bedtime < threshold }.map { Double($0.asleepMinutes) }.mean
        func cost(_ xs: [NightRecord]) -> Int? {
            guard let n = normal, let m = xs.map({ Double($0.asleepMinutes) }).mean else { return nil }
            return Int((m - n).rounded())
        }
        return (cost(lateNights.filter(\.alarmUsed)), cost(lateNights.filter { !$0.alarmUsed }))
    }

    // MARK: Why do I feel off?

    /// A concrete thing to try for one reason.
    func tryThis(for reason: OffReason) -> String {
        switch reason.topic {
        case .sleepDebt?:
            return "Be in bed by \(Clock.format(tonightAimBedtime)) tonight for your \(tonightNeedText). \(debtPaybackSentence)"
        case .lateNight?:
            return "Be in bed by \(Clock.format(store.data.bedtime)) tonight and tomorrow. It usually takes two normal nights to bounce back."
        case .luteal?:
            // One small number, only on the days it's added (Park 9, Liu 5).
            let sleep = cycleSleepAllowance
                ? "Tonight's need has about 10 minutes added; sleep may feel lighter now, and extra rest is fine. "
                : "Sleep may feel lighter now, and extra rest is fine. "
            return sleep + (hidesEffortTargets ? "Go easy on yourself. " : "Train as planned, easier if you feel flat. ") + lutealEasesLine
        case .illness?:
            return hidesEffortTargets
                ? "Take an easy day: extra sleep and plenty of fluids."
                : "Take an easy day: extra sleep, plenty of fluids, no hard training."
        case .stress?:
            return hidesEffortTargets
                ? "Try five minutes of slow breathing (in for 4, out for 6), or a few minutes outside."
                : "Try five minutes of slow breathing (in for 4, out for 6), or a short walk outside."
        case .caffeineCutoff?:
            if caffeineCutoffBeforeWake {
                return "Tomorrow, keep it to one small drink (up to about \(caffeineLargestDoseAtWake) mg) soon after you wake. On your birth control, caffeine stays in your body \(caffeineLongerPhrase)."
            }
            return "Have your last caffeine before \(Clock.format(caffeineCutoff)) tomorrow."
        case .daylight?:
            return "Get 10 to 20 minutes outside, ideally before noon."
        default:
            return "Go easy on yourself today and keep your usual bedtime."
        }
    }

    // MARK: Achievements

    struct Badge: Identifiable, Hashable {
        var id: String { title }
        var title: String
        var systemImage: String
        var accent: Accent
        var progress: Int
        var goal: Int
        /// What earns it, in plain words.
        var howTo: String
        var earned: Bool { progress >= goal }
        var fraction: Double { goal > 0 ? min(Double(progress) / Double(goal), 1) : 0 }
    }

    /// Badges worked out from what's already tracked and logged.
    var badges: [Badge] {
        let cal = Calendar.current
        let streakList = streaks
        let onTime = streakList.first { $0.title == "In bed on time" }
        let need = streakList.first { $0.title == "Met your sleep need" }
        /// "N in a row" badges: earned once the longest run reached N; until
        /// then progress is the current streak (round 3, N7).
        func inARow(_ s: StreakInfo?, _ goal: Int) -> Int {
            guard let s else { return 0 }
            return s.longest >= goal ? goal : min(s.current, goal)
        }
        let waterByDay = Dictionary(grouping: store.data.waterLog) { cal.startOfDay(for: $0.date) }
        let waterDays = waterByDay.values.filter { $0.map(\.ml).reduce(0, +) >= store.data.waterGoalML }.count
        let bed = Clock.format(store.data.bedtime)
        let test = cutoffTest
        // On time on most of the last 30 nights, not 30 in a row: one off
        // night doesn't wipe out a month (Laurent F12).
        let today = cal.startOfDay(for: .now)
        let onTimeOf30 = realNights.filter { n in
            let ago = cal.dateComponents([.day], from: cal.startOfDay(for: n.wakeDay), to: today).day ?? 99
            return ago >= 0 && ago < 30 && n.sleepOnset <= store.data.bedtime + 20
        }.count
        var out: [Badge] = [
            Badge(title: "First week tracked", systemImage: "moon.stars.fill", accent: .purple,
                  progress: min(realNights.count, 7), goal: 7, howTo: "Wear your Watch to bed for 7 nights."),
            Badge(title: "7 nights on time", systemImage: "bed.double.fill", accent: .indigo,
                  progress: inARow(onTime, 7), goal: 7, howTo: "Fall asleep within 20 minutes of your \(bed) bedtime 7 nights in a row."),
            Badge(title: "14 check-ins", systemImage: "checkmark.circle.fill", accent: .mint,
                  progress: min(store.data.checkIns.count, 14), goal: 14, howTo: "Do your morning check-in 14 times."),
            Badge(title: "Slept your need 5 nights running", systemImage: "zzz", accent: .blue,
                  progress: inARow(need, 5), goal: 5, howTo: "Get at least your sleep need 5 nights in a row."),
            Badge(title: "First coffee or tea logged", systemImage: "cup.and.saucer.fill", accent: .yellow,
                  progress: min(store.data.drinkLog.count, 1), goal: 1, howTo: "Log a coffee, tea or energy drink."),
            Badge(title: "Hydrated week", systemImage: "drop.fill", accent: .blue,
                  progress: min(waterDays, 7), goal: 7, howTo: "Reach your water goal on 7 days."),
            Badge(title: "Caffeine scientist", systemImage: "flask.fill", accent: .coral,
                  progress: min(test.nightsLogged, test.target), goal: test.target,
                  howTo: "Log your caffeine for \(test.target) days to find your own cutoff time."),
            Badge(title: "On time 25 of 30 nights", systemImage: "flame.fill", accent: .orange,
                  progress: min(onTimeOf30, 25), goal: 25,
                  howTo: "Fall asleep within 20 minutes of your \(bed) bedtime on 25 of your last 30 nights. A few off nights are fine."),
        ]
        // A period-count goal only where periods are expected: hidden on
        // methods where bleeding is rare or has stopped, and a pack goal
        // (withdrawal bleeds in the break) for the pill, ring and patch.
        if store.data.cycleSetup != .notTracking, !usesBleedingWording {
            let starts = Self.mergedPeriodStarts(health: [], logged: store.data.flowLog).count
            let badge = usesPackWording
                ? Badge(title: "Two breaks tracked", systemImage: "heart.fill", accent: .pink,
                        progress: min(starts, 2), goal: 2, howTo: "Log your bleed in two break weeks in the app.")
                : Badge(title: "Full cycle tracked", systemImage: "heart.fill", accent: .pink,
                        progress: min(starts, 2), goal: 2, howTo: "Log the start of two periods in the app.")
            out.insert(badge, at: min(5, out.count))
        }
        // No water target badge with an eating-disorder history.
        if hidesEffortTargets { out.removeAll { $0.title == "Hydrated week" } }
        return out
    }

    /// The locked badge she's closest to.
    var nextBadge: Badge? {
        badges.filter { !$0.earned }.max { $0.fraction < $1.fraction }
    }
}
