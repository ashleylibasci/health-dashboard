import Foundation
import Combine
import SwiftUI
import HealthCore

/// Everything the screens show. Raw inputs come from Apple Health (or the
/// sample data); every number on screen is derived through HealthCore.
@MainActor
final class AppModel: ObservableObject {
    let store: DataStore
    let health = HealthKitService()
    private var storeChanges: AnyCancellable?

    // MARK: Raw inputs

    /// True until Apple Health has 14 nights of sleep. Screens then show the
    /// example data with `SampleDataBanner`.
    @Published var usingSampleData = true
    @Published var loading = false
    /// Real nights read from Apple Health (0 in the simulator).
    @Published var realNightCount = 0
    /// False when no real sleep ended during this app day or the evening
    /// before it ("No sleep recorded last night"). It only goes stale once
    /// the next app day has started, never at 2am.
    @Published var lastNightIsFresh = true
    /// Last night comes from Apple Health (also during the example-data
    /// period, as soon as one real night exists).
    @Published var lastNightIsReal = false
    /// False when Apple Health has no HRV or resting heart rate for today or
    /// yesterday. The deltas are then 0.
    @Published var hasHeartData = true
    /// Work-night or free-night sleep is still missing, so the chronotype is
    /// a default.
    @Published var chronotypeIsLearning = false
    /// The last time a refresh finished.
    @Published var lastRefreshed: Date?
    /// The last Apple Health write failed (a log is kept in the app either way).
    @Published var healthWriteFailed = false
    /// Her own averages over recent days, once there are at least 7.
    @Published private(set) var personalRecoveryUsual: Int?
    @Published private(set) var personalEnergyUsual: Int?
    /// Days of her own recovery readings so far (her usual needs 7).
    @Published private(set) var recoveryDaysLearned = 0
    /// Her own day-to-day spread of recovery scores (standard deviation),
    /// once there are 14 days. Scales the recovery labels.
    @Published private(set) var personalRecoverySpread: Double?
    /// Period starts read from Apple Health. Logged bleeds are merged in on
    /// the fly (`mergedPeriodStarts`).
    @Published var healthPeriodStarts: [Date] = []
    /// Pill doses marked taken in Apple Health (Apple's Medications or
    /// another app), when she turned that on (`AppModel+Pill.swift`).
    @Published var healthPillDoses: [Date] = []
    /// Apple's Medications has a reminder schedule for her pill, so this app
    /// sends only the repeat (never two reminders at once).
    @Published var healthPillHasSchedule = false
    /// Moods from Apple's State of Mind log by app day, 1–5 (F2,
    /// `MoodHealth`). Her own taps here win on the same day.
    @Published var healthMoodByDay: [Date: Int] = [:]

    /// Where Apple Health stands, for the accuracy and settings screens.
    enum HealthConnection: Equatable {
        /// No Apple Health on this device (simulator, iPad).
        case unavailable
        /// She chose "Use sample data" in Settings.
        case sampleChosen
        /// She hasn't been asked for access yet.
        case notAsked
        /// Asked, but no sleep has come through: access may be off in
        /// Settings, or no night has been recorded yet. (Apple never tells an
        /// app whether reading is allowed.)
        case noSleepYet
        /// Real nights are coming through.
        case connected
    }
    @Published private(set) var healthConnection: HealthConnection = .notAsked
    /// Saving caffeine and water to Apple Health is switched off in Settings.
    @Published private(set) var healthWriteDenied = false
    /// She chose example data in Settings; opening the app doesn't switch
    /// back to Apple Health until she taps Connect.
    @Published private(set) var prefersSampleData = UserDefaults.standard.bool(forKey: AppModel.sampleDataKey)
    static let sampleDataKey = "useSampleData"
    /// Wake days (calendar midnight) of the nights that came from Apple
    /// Health. During the first 14 nights `nights` mixes these with
    /// example nights; `isRealNight` tells them apart.
    @Published private(set) var realNightDays: Set<Date> = []
    /// Today's HRV and resting heart rate are her own readings (also during
    /// the example-data period, once there's a baseline to compare with).
    @Published private(set) var heartIsReal = false
    /// A resting heart rate baseline (5+ days) exists. Without one there is
    /// no stress level, never a made-up "High".
    @Published private(set) var restingHRBaselineKnown = true
    /// HRV comes from readings taken during sleep (fair night to night),
    /// rather than daily averages.
    @Published private(set) var hrvIsOvernight = false
    /// Daytime HRV baseline for stress (median of daily averages, 30 days).
    @Published private(set) var stressHRVBaseline: Double?
    /// Her heart rate in still, awake hours over the last 14 days. Stress is
    /// measured from it once there are enough hours (round 4, Brandt F5).
    @Published private(set) var stressStillBaseline: StressModel.StillBaseline?
    /// How much her resting heart rate (bpm) and HRV (% of usual) move day
    /// to day over the 30-day baseline window, once there are 10 days. The
    /// sick check and the HRV bands scale with them (round 4, Brandt F6/F9).
    @Published private(set) var restingHRSpread: Double?
    @Published private(set) var hrvSpreadPct: Double?
    /// Her own usual range (10th–90th percentile of the last 30 days) for
    /// the Today dials (round 4, Brandt F10).
    @Published private(set) var hrvUsualRange: ClosedRange<Double>?
    @Published private(set) var restingHRUsualRange: ClosedRange<Double>?
    /// Her latest weight from Apple Health (last year), for "hard training"
    /// and an active hour. Nil without one.
    @Published private(set) var bodyMassKg: Double?
    /// Most of her logged cycles ran longer than 45 days: there is no usual
    /// length, and the cycle shows the irregular view.
    @Published private(set) var cycleLengthsRunLong = false
    /// Her own usual cycle length (20–45 day cycles), nil until two period
    /// starts give one. `cycleLength` falls back to a typical 29 without it.
    @Published private(set) var personalCycleLength: Int?
    /// Daylight minutes by calendar day (Apple Health counts calendar days).
    @Published var daylightByDay: [Date: Double] = [:]
    /// Active energy on the 14 days before yesterday, for "hard training".
    @Published var activeCaloriesEarlier: [Double] = []
    private var refreshAgain = false

    @Published var nights: [NightRecord] = []
    @Published var sessions: [SleepSession] = []
    @Published var mornings: [Morning] = []
    @Published var lastWeek: [DaySummary] = []
    @Published var lastNight = LastNight.sample
    @Published var hrv = SampleData.hrv
    @Published var restingHR = SampleData.restingHR
    @Published var hrvDeltaPct = SampleData.hrvDeltaPct
    @Published var restingHRDelta = SampleData.restingHRDelta
    @Published var daylightToday = SampleData.daylightToday
    /// Daylight minutes today before 11am (the morning light target, H-C5).
    @Published var morningDaylightToday = SampleData.morningDaylightToday
    @Published var stepsToday = SampleData.stepsToday
    @Published var cycleDay: Int?
    @Published var cycleLength = SampleData.cycleLength
    @Published var workNights = SampleData.workNights
    @Published var freeNights = SampleData.freeNights
    /// Today's hourly heart rate / HRV / steps, for stress.
    @Published var stressSamples: [StressModel.Sample] = SampleData.stressSamples
    @Published var respiratoryRateDelta: Double? = SampleData.respiratoryRateDelta
    @Published var wristTempDelta: Double? = SampleData.wristTempDelta
    @Published var vo2Max: Double? = SampleData.vo2Max
    @Published var vo2MaxHistory: [(date: Date, value: Double)] = SampleData.vo2MaxHistory()
    @Published var activeCalories: Double = SampleData.activeCalories
    @Published var restingCalories: Double = SampleData.restingCalories
    /// Active energy yesterday, for the sick check's training-day context.
    /// Nil with example data or no reading.
    @Published var activeCaloriesYesterday: Double?

    /// Last night. Times are minutes from midnight of the app day she woke
    /// in, the same axis as `now`: a 7:30am wake is 450, and a 3:30am wake
    /// before the rollover is 1650 (still the evening before).
    struct LastNight: Hashable {
        var bedtime: Minutes, onset: Minutes, wake: Minutes, asleep: Int
        var wokeFromLight: Bool
        var stageMinutes: [SleepStage: Int]
        var segments: [StageSegment]
        /// When she woke (nil for the example night).
        var wakeDate: Date? = nil
        static let sample = LastNight(bedtime: SampleData.lastNight.bedtime, onset: SampleData.lastNight.onset,
                                      wake: SampleData.lastNight.wake, asleep: SampleData.lastNight.asleep,
                                      wokeFromLight: SampleData.lastNight.wokeFromLight,
                                      stageMinutes: SampleData.lastNightStages, segments: [])
    }

    /// The anchor today's recovery is scored around (HealthCore's typical
    /// value). `recoveryUsual` is her own average of scores made this way.
    static let recoveryAnchor = 78
    static let typicalEnergy = 74
    /// Nights of real sleep before the app switches from example data.
    static let nightsNeeded = 14
    /// The cycle length used until her own logs give one.
    static let typicalCycleLength = 29

    init(store: DataStore) {
        self.store = store
        AppDay.rolloverMinutes = AppDay.rollover(forBedtime: store.data.bedtime)
        applySampleData()
        recomputeCycle()
        // Screens that only watch the model still refresh when logs change.
        storeChanges = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        store.onChange = { [weak self] old, new in self?.storeDidChange(from: old, to: new) }
    }

    // MARK: The app day

    /// The rollover today (4:00am, or later after a late planned bedtime),
    /// or yesterday's before it. Everything "today" (caffeine, water, mood,
    /// drinks) counts from here.
    var appDayStart: Date { AppDay.start() }
    /// Midnight of the app day. `now` and today's zones are minutes from here.
    var appDayDate: Date { AppDay.day() }
    func inAppDay(_ date: Date) -> Bool { AppDay.contains(date) }
    /// The morning after tonight: the wake day for bedtime, up-by and the alarm.
    var nextWakeDay: Date { Calendar.current.date(byAdding: .day, value: 1, to: appDayDate) ?? appDayDate }

    // MARK: Derived numbers

    /// The current time in minutes from midnight of the app day: 2pm is 840,
    /// and 12:30am (still the evening before) is 1470.
    var now: Minutes { AppDay.minutes(.now, relativeTo: appDayDate) }

    var sleepNeed: SleepNeedEstimate { SleepNeedEstimator.estimate(from: nights, userAdjustment: store.data.sleepNeedAdjustment) }

    var sleepDebt: Int {
        SleepDebt.minutes(need: sleepNeed.minutes, lastNightsNewestFirst: nights.sorted { $0.wakeDay > $1.wakeDay }.map(\.asleepMinutes))
    }

    /// The calendar day last night ended on (today for the example night).
    var lastNightWakeDay: Date { Calendar.current.startOfDay(for: lastNight.wakeDate ?? .now) }

    /// Debt from the nights before last night. Last night's own shortfall is
    /// already in the energy model's "asleep" input, so counting it in the
    /// debt too would count it twice.
    var sleepDebtBeforeLastNight: Int { sleepDebt(before: lastNightWakeDay) }

    /// Debt from the nights that ended before `day`.
    func sleepDebt(before day: Date) -> Int {
        let before = nights.filter { $0.wakeDay < day }.sorted { $0.wakeDay > $1.wakeDay }
        return SleepDebt.minutes(need: sleepNeed.minutes, lastNightsNewestFirst: before.map(\.asleepMinutes))
    }

    /// Pill, ring or patch: today's day in the pack (1…packLength), by the
    /// calendar day (the day a pill is taken). From the pack start she set,
    /// rolling on into later packs; a pack start in the future means the
    /// current pack ends early (she skipped a break). Without one, an
    /// estimate that treats her last bleed start as pack day activeDays + 3
    /// (`packBleedStartDay`); never for continuous use. Nil when neither is
    /// known: then no pack is shown, only "Set where you are in your pack".
    var packDay: Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let length = max(store.data.packLength, 1)
        let active = min(max(store.data.packActiveDays, 1), length)
        if let start = store.data.packStartDate {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: today).day ?? 0
            if days < 0 { return max(1, active + 1 + days) }
            return days % length + 1
        }
        guard let bc = store.birthControl, bc.hasBreakWeek, active < length,
              let bleed = Self.mergedPeriodStarts(health: healthPeriodStarts, logged: store.data.flowLog).last else { return nil }
        let days = cal.dateComponents([.day], from: bleed, to: today).day ?? 0
        return ((packBleedStartDay - 1 + days) % length + length) % length + 1
    }

    /// The pack day a withdrawal bleed usually starts on with her pack type
    /// (day 24 of 21+7, day 27 of 24+4).
    var packBleedStartDay: Int {
        CycleDisplay.bleedStartPackDay(activeDays: store.data.packActiveDays, packLength: store.data.packLength)
    }

    /// "Today is pill `day`": sets the pack start so today is that day.
    func setPackDay(_ day: Int) {
        let d = min(max(day, 1), max(store.data.packLength, 1))
        let today = Calendar.current.startOfDay(for: .now)
        setPackStart(Calendar.current.date(byAdding: .day, value: -(d - 1), to: today) ?? today)
    }

    /// The day she took pill 1 (put in the ring, put on the patch) of the
    /// current pack. A date in the future is when her next pack starts
    /// (skipping a break).
    func setPackStart(_ date: Date) {
        store.data.packStartDate = Calendar.current.startOfDay(for: date)
        store.data.packCheckDismissed = nil
    }

    /// Changes the pack type (21+7, 24+4, continuous) and keeps the day she
    /// started this pack, so the pill she's on stays the same.
    func setPackType(activeDays: Int, packLength: Int = 28) {
        let length = min(max(packLength, 1), 35)
        if store.data.packLength != length { store.data.packLength = length }
        let active = min(max(activeDays, 1), length)
        if store.data.packActiveDays != active { store.data.packActiveDays = active }
    }

    /// What the cycle screens show: phases, a pill pack, or nothing, depending
    /// on setup and birth control. Methods that stop ovulation never show
    /// ovulation or luteal phases.
    var cycleDisplay: CycleDisplay {
        CycleDisplay.make(tracking: store.data.cycleSetup != .notTracking,
                          irregular: showsIrregularCycle,
                          birthControl: store.birthControl, cycleDay: cycleDay, cycleLength: cycleLength,
                          packDay: packDay, activeDays: store.data.packActiveDays, packLength: store.data.packLength,
                          periodLength: periodLength)
    }

    /// Her usual period length, learned from the bleeding days she logged
    /// (the median of her recent periods), else a typical 5. The legend, the
    /// calendar and the predicted period all use it (round 3, N10).
    var periodLength: Int {
        let bleeding = store.data.flowLog.filter { $0.flow != .none && $0.flow != .spotting }.map(\.date)
        return CycleEstimator.periodLength(bleedDays: bleeding) ?? CycleEstimator.typicalPeriodLength
    }

    /// The phase on cycle `day`, with her own period length.
    func cyclePhase(day: Int, length: Int) -> CyclePhase {
        CycleEstimator.phase(day: day, length: length, periodLength: periodLength)
    }

    /// Irregular view: she said so, PCOS, or her cycles run longer than 45
    /// days (no usual length to count against).
    var showsIrregularCycle: Bool {
        store.data.cycleSetup == .irregular || store.data.conditions.contains("PCOS") || cycleLengthsRunLong
    }

    /// Why the irregular view is shown when she didn't pick it herself:
    /// "pcos", "long" or nil.
    var irregularReason: String? {
        guard store.data.cycleSetup != .irregular else { return nil }
        if store.data.conditions.contains("PCOS") { return "pcos" }
        return cycleLengthsRunLong ? "long" : nil
    }

    /// `cycleLength` is her own (from two or more period starts), not the
    /// typical 29.
    var cycleLengthIsPersonal: Bool { personalCycleLength != nil }

    var isLateLuteal: Bool { cycleDisplay.isLateLuteal }

    /// The sick check thinks she may be fighting something: tonight's need
    /// gets the extra 30 minutes.
    var unwellTonight: Bool { illness.confidence == .medium || illness.confidence == .high }

    /// The small cycle allowance on tonight's need (Park 9, Liu 5): about 10
    /// minutes in the last 5 days before a natural-cycle period (the end of
    /// late luteal) and the first 2 days of bleeding, when sleep may feel
    /// lighter. Never on methods that stop ovulation (no `.phases` then).
    var cycleSleepAllowance: Bool {
        guard case let .phases(day, length, _) = cycleDisplay, day <= length else { return false }
        return (isLateLuteal && day > length - 5) || day <= 2
    }

    var tonightNeed: TonightNeed { TonightNeed(base: sleepNeed.minutes, debt: sleepDebt, lateLuteal: cycleSleepAllowance, unwell: unwellTonight) }

    var wakeHistory: WakeHistory { WakeHistory.analyze(mornings) }

    var sleepCycleLength: Int { usingSampleData ? 92 : WakePlanner.cycleLength(from: sessions) }

    /// The Watch listens for stirring for the last 25 minutes before the
    /// latest wake time (a smart-alarm session lasts 30 minutes and keeps 5
    /// for ringing), so the window is 22 minutes before a cycle end to 3
    /// after, or the 25 minutes up to up-by.
    static let alarmWindowLead = 22

    /// Tomorrow's wake plan, by default from tonight's one bedtime
    /// (`tonightBedtime`, her best times).
    func wakePlan(upBy: Minutes? = nil, bedtime: Minutes? = nil) -> WakePlan? {
        let bed = bedtime ?? tonightBedtime
        let deadline = upBy ?? store.data.upBy
        return WakePlanner.plan(.init(bedtime: bed, latency: bestTimes.latency, cycleLength: sleepCycleLength,
                                      deadline: deadline, tonightNeed: tonightNeed.total,
                                      bestWindow: wakeHistory.bestWindow,
                                      currentAlarmLatest: store.data.smartAlarmEnabled ? activeAlarmOverride?.end : nil,
                                      windowLength: Self.alarmWindowLead,
                                      clockShift: clockShiftTonight(bedtime: bed, deadline: deadline)))
    }

    /// Minutes the clocks jump between tonight's bedtime and the morning's
    /// deadline: −60 the night they fall back, +60 when they spring forward.
    func clockShiftTonight(bedtime: Minutes, deadline: Minutes, calendar: Calendar = .current) -> Int {
        let bed = Clock.date(bedtime, relativeTo: nextWakeDay, calendar: calendar)
        let up = Clock.date(deadline, relativeTo: nextWakeDay, calendar: calendar)
        let elapsed = Int((up.timeIntervalSince(bed) / 60).rounded())
        return (deadline - bedtime) - elapsed
    }

    /// A wake window she set for one particular morning (exam mode), while
    /// that morning is still ahead.
    var activeAlarmOverride: AppData.AlarmOverride? {
        guard let o = store.data.alarmOverride, AppDay.date(o.end, relativeTo: o.wakeDay) > .now else { return nil }
        return o
    }

    var recoveryUsual: Int { personalRecoveryUsual ?? Self.recoveryAnchor }
    var energyUsual: Int { personalEnergyUsual ?? Self.typicalEnergy }
    /// True when both usuals are her own averages rather than typical values.
    var usualsArePersonal: Bool { personalRecoveryUsual != nil && personalEnergyUsual != nil }
    var recoveryUsualIsPersonal: Bool { personalRecoveryUsual != nil }
    var energyUsualIsPersonal: Bool { personalEnergyUsual != nil }

    /// A natural cycle's own shift today is allowed for (`cycleHeartShift`),
    /// and on the pill her own break-week shift (`packHeartAllowanceToday`).
    var recovery: Int {
        let pack = packHeartAllowanceToday
        return Recovery.score(usual: Double(Self.recoveryAnchor), hrvDeltaPct: hrvDeltaPct - (pack?.hrvPct ?? 0),
                              restingHRDelta: restingHRDelta - (pack?.restingHR ?? 0),
                              sleepShortfall: max(0, sleepNeed.minutes - lastNight.asleep - 15), cycle: cycleHeartShift)
    }
    /// The label for today's shown recovery (`recoveryShown`); "" when there
    /// is no number.
    var recoveryLabel: String { recoveryShown.map(recoveryLabel(for:)) ?? "" }
    /// The label for any recovery score, with bands scaled to how much her
    /// own score usually moves. Use this instead of `Recovery.label`.
    func recoveryLabel(for score: Int) -> String {
        recoveryLevel(for: score).label
    }
    /// The band for any recovery score: the label and the effort target on
    /// Energy both come from it, so they always agree.
    func recoveryLevel(for score: Int) -> Recovery.Level {
        Recovery.level(score, usual: recoveryUsual, spread: personalRecoverySpread)
    }
    /// Recovery today leans on example HRV and resting heart rate (the first
    /// 14 nights, before her own baseline exists).
    var recoveryIsExample: Bool { usingSampleData && !heartIsReal }

    var chronotype: Chronotype? { Chronotype.compute(workNights: workNights, freeNights: freeNights) }

    private var habitualOnset: Minutes {
        let onsets = workNights.isEmpty ? nights.map(\.sleepOnset) : workNights.map(\.onset)
        guard !onsets.isEmpty else { return 1440 + tonightBedtime + 15 }
        return 1440 + onsets.reduce(0, +) / onsets.count
    }
    /// Her body clock's mid-sleep: from free (no-alarm) nights when there
    /// are some (an alarm cuts work-night sleep short, so their mid-sleep
    /// runs early), else from work nights.
    private var midSleep: Minutes {
        if let c = chronotype { return c.midSleepFreeCorrected }
        let mids = (workNights.isEmpty ? nights.map { ($0.sleepOnset + $0.wake) / 2 } : workNights.map { ($0.onset + $0.wake) / 2 })
        guard !mids.isEmpty else { return 262 }
        return ((mids.reduce(0, +) / mids.count) % 1440 + 1440) % 1440
    }

    var energyToday: EnergyDay {
        EnergyModel.day(.init(wake: lastNight.wake, asleepMinutes: lastNight.asleep, sleepDebt: sleepDebtBeforeLastNight,
                              habitualMidSleep: midSleep, habitualSleepOnset: habitualOnset,
                              wokeFromLightSleep: lastNight.wokeFromLight, bedtime: 1440 + tonightBedtime,
                              sleepNeed: sleepNeed.minutes))
    }

    /// Tomorrow after tonight's plan: debt through last night, tonight's
    /// planned sleep as "asleep".
    var energyTomorrow: EnergyDay {
        let plan = wakePlan()
        return EnergyModel.day(.init(wake: plan?.wake ?? 502, asleepMinutes: plan?.asleep ?? 460, sleepDebt: sleepDebt,
                                     habitualMidSleep: midSleep, habitualSleepOnset: habitualOnset,
                                     wokeFromLightSleep: true, bedtime: 1440 + tonightBedtime,
                                     sleepNeed: sleepNeed.minutes))
    }

    /// The energy score a past night led to, with the same model as today's:
    /// debt from the nights before it, and that evening's real bedtime (the
    /// next night's sleep onset) rather than today's setting.
    func energyScore(for night: NightRecord) -> Int {
        let cal = Calendar.current
        let nextDay = cal.date(byAdding: .day, value: 1, to: night.wakeDay) ?? night.wakeDay
        let evening = nights.first { cal.isDate($0.wakeDay, inSameDayAs: nextDay) }.map { 1440 + $0.sleepOnset } ?? 1440 + store.data.bedtime
        return EnergyModel.day(.init(wake: night.wake, asleepMinutes: night.asleepMinutes, sleepDebt: sleepDebt(before: night.wakeDay),
                                     habitualMidSleep: midSleep, habitualSleepOnset: habitualOnset,
                                     wokeFromLightSleep: night.wokeFromLightSleep ?? true, bedtime: evening,
                                     sleepNeed: sleepNeed.minutes)).score
    }

    /// Older callers: `sleepDebt` is ignored (the debt before the night is used).
    func energyScore(for night: NightRecord, sleepDebt debt: Int) -> Int { energyScore(for: night) }

    /// In the luteal phase HRV runs a few percent lower on its own, so a dip
    /// of up to 5% isn't taken off the bank (Park 14).
    var energyBankAtWake: Double {
        let hrv = inLutealPhase ? min(hrvDeltaPct + 5, max(hrvDeltaPct, 0)) : hrvDeltaPct
        return EnergyBank.atWake(asleepMinutes: lastNight.asleep, sleepDebt: sleepDebtBeforeLastNight, hrvDeltaPct: hrv)
    }
    var energyBankNow: Double { EnergyBank.level(atWake: energyBankAtWake, hoursAwake: Double(max(0, now - lastNight.wake)) / 60) }
    var energyBankAtBedtime: Double { EnergyBank.level(atWake: energyBankAtWake, hoursAwake: Double(max(0, 1440 + tonightBedtime - lastNight.wake)) / 60) }

    // MARK: Caffeine and water today

    /// Caffeine stays about one and a half times as long on the combined pill
    /// (estrogen slows the liver enzyme CYP1A2), and probably on the ring and
    /// patch: about 7 hours instead of 5.
    var caffeineHalfLifeHours: Double {
        switch store.birthControl {
        case .combinedPill?, .ring?, .patch?: return CaffeineModel.estrogenHalfLifeHours
        default: return CaffeineModel.typicalHalfLifeHours
        }
    }

    /// "about one and a half times as long", hedged with "probably" on the
    /// ring and patch (the study was of pill users).
    var caffeineLongerPhrase: String {
        store.birthControl == .combinedPill ? "about one and a half times as long" : "probably about one and a half times as long"
    }

    /// Drinks logged today (since 4am), oldest first.
    var todaysDrinks: [AppData.LoggedDrink] { AppData.today(store.data.drinkLog, date: \.date).sorted { $0.date < $1.date } }

    /// Today's caffeine at the times you logged it, in app-day minutes (a
    /// 12:15am drink is 1455). Only what she logged, also with example
    /// data, so every screen agrees on today's total.
    var caffeineDoses: [CaffeineDose] {
        let day = appDayDate
        return todaysDrinks.map { CaffeineDose(time: AppDay.minutes($0.date, relativeTo: day), mg: $0.mg) }
    }

    var todaysWater: [AppData.WaterEntry] { AppData.today(store.data.waterLog, date: \.date).sorted { $0.date < $1.date } }
    var waterTodayML: Double { todaysWater.map(\.ml).reduce(0, +) }

    /// For the reference coffee every caffeine line names (12 oz drip, 140 mg),
    /// so the cutoff and the copy describe the same drink (round 3, H10).
    var caffeineCutoff: Minutes {
        CaffeineModel.cutoff(bedtime: 1440 + tonightBedtime, halfLifeHours: caffeineHalfLifeHours,
                             mg: Double(Self.referenceCoffee.caffeineMg))
    }
    var caffeineMgToday: Int { caffeineDoses.map(\.mg).reduce(0, +) }
    var caffeineAtBedtime: Int {
        Int(CaffeineModel.amount(at: 1440 + tonightBedtime, doses: caffeineDoses, halfLifeHours: caffeineHalfLifeHours).rounded())
    }
    var caffeineTimingToday: CaffeineModel.Timing { CaffeineModel.timing(energy: energyToday, cutoff: caffeineCutoff, firstDrinkAt: caffeineDoses.first?.time) }
    var caffeineTimingTomorrow: CaffeineModel.Timing { CaffeineModel.timing(energy: energyTomorrow, cutoff: caffeineCutoff, firstDrinkAt: nil) }

    var weekRecap: WeekRecap? {
        WeekRecap.make(days: lastWeek, need: sleepNeed.minutes, bestWindow: wakeHistory.bestWindow, lateThreshold: lateBedtimeThreshold)
    }

    // MARK: Loading

    /// Settings > "Use sample data": shows the example data and keeps it
    /// (opening the app doesn't switch back) until she taps Connect.
    func loadSample() {
        setPrefersSampleData(true)
        applySampleData()
        recomputeCycle()
        finishRefresh()
    }

    private func setPrefersSampleData(_ on: Bool) {
        prefersSampleData = on
        UserDefaults.standard.set(on, forKey: Self.sampleDataKey)
        if on { healthConnection = .sampleChosen }
    }

    /// Example values for everything read from Apple Health.
    private func applySampleData() {
        usingSampleData = true
        nights = SampleData.nights()
        if DemoMode.pillHistory { nights = DemoMode.pillHistoryNights(nights) }
        realNightDays = []
        sessions = []
        mornings = SampleData.mornings()
        lastWeek = SampleData.lastWeek()
        lastNight = .sample
        lastNightIsFresh = true
        lastNightIsReal = false
        hasHeartData = true
        heartIsReal = false
        restingHRBaselineKnown = true
        hrvIsOvernight = false
        stressHRVBaseline = SampleData.baselineHRV
        stressStillBaseline = nil
        restingHRSpread = nil; hrvSpreadPct = nil
        hrvUsualRange = nil; restingHRUsualRange = nil
        bodyMassKg = nil
        chronotypeIsLearning = false
        personalRecoveryUsual = nil
        personalEnergyUsual = nil
        personalRecoverySpread = nil
        recoveryDaysLearned = 0
        hrv = SampleData.hrv; restingHR = SampleData.restingHR
        hrvDeltaPct = SampleData.hrvDeltaPct; restingHRDelta = SampleData.restingHRDelta
        daylightToday = SampleData.daylightToday; stepsToday = SampleData.stepsToday
        morningDaylightToday = SampleData.morningDaylightToday
        daylightByDay = [:]
        workNights = SampleData.workNights; freeNights = SampleData.freeNights
        stressSamples = SampleData.stressSamples
        respiratoryRateDelta = SampleData.respiratoryRateDelta; wristTempDelta = SampleData.wristTempDelta
        vo2Max = SampleData.vo2Max; vo2MaxHistory = SampleData.vo2MaxHistory()
        activeCalories = SampleData.activeCalories; restingCalories = SampleData.restingCalories
        activeCaloriesYesterday = nil
        activeCaloriesEarlier = []
        if DemoMode.fuel {
            // A hard training day (the water goal goes up).
            activeCalories = 650
        }
        if DemoMode.sick {
            // Resting HR up, HRV down, breathing and wrist temperature up.
            restingHRDelta = 6; hrvDeltaPct = -24
            respiratoryRateDelta = 1.6; wristTempDelta = 0.7
        }
    }

    /// Settings / onboarding "Connect Apple Health": asks for access (the
    /// sheet only shows the first time), then loads real data. Stays on
    /// example data if Health isn't available (simulator) or there are
    /// fewer than 14 nights. A failed refresh keeps whatever was showing.
    func connectHealth() async {
        setPrefersSampleData(false)
        await syncWithHealth()
        BackgroundHealth.shared.start(self)
    }

    private func syncWithHealth() async {
        guard HealthKitService.isAvailable, !DemoMode.isOn else {
            healthConnection = .unavailable
            pushToWatch()
            await updateNudges()
            return
        }
        do {
            try await health.requestAuthorization()
            try await refresh()
        } catch {
            await updateHealthConnection()
            pushToWatch()
        }
    }

    /// Called when the app comes to the foreground: new day, new numbers.
    func becameActive() async {
        AppDay.rolloverMinutes = AppDay.rollover(forBedtime: store.data.bedtime)
        recordTimeZone()
        importPendingDrinks()
        importPendingLogs()
        Task { await CalendarImport.shared.check(model: self) }
        guard store.data.onboarded else {
            pushToWatch()
            return
        }
        if prefersSampleData {
            applySampleData()
            recomputeCycle()
            finishRefresh()
        } else {
            await syncWithHealth()
        }
    }

    /// The Watch asked for numbers (it just opened): send what we have
    /// right away (stamped with when it was read), then refresh from Apple
    /// Health, which sends again when it's done.
    func answerSnapshotRequest() {
        pushToWatch()
        let old = lastRefreshed.map { Date().timeIntervalSince($0) > 5 * 60 } ?? true
        guard old, store.data.onboarded, !prefersSampleData, HealthKitService.isAvailable, !DemoMode.isOn else { return }
        Task { try? await refresh() }
    }

    private func updateHealthConnection() async {
        if prefersSampleData { healthConnection = .sampleChosen; return }
        guard HealthKitService.isAvailable, !DemoMode.isOn else { healthConnection = .unavailable; return }
        if realNightCount > 0 {
            healthConnection = .connected
        } else {
            healthConnection = await health.needsAuthorizationRequest() ? .notAsked : .noSleepYet
        }
        healthWriteDenied = health.caffeineWriteDenied
    }

    /// Her heart readings by day: HRV from readings taken during each night
    /// when there are enough (5+ nights), else daily averages.
    struct HeartData {
        var hrvByDay: [Date: Double] = [:]
        var dailyHRV: [Date: Double] = [:]
        var rhrByDay: [Date: Double] = [:]
        var overnight = false
        /// Days left out of every "your usual" (E1, `baselineExclusions`).
        var excluded: Set<Date> = []
    }

    /// Also reads the older nights of the six-month trends (`olderTrendNights`).
    func loadHeart(main: [SleepSession], days: Int) async -> HeartData {
        let daily = (try? await health.dailyAverage(.heartRateVariabilitySDNN, unit: .msUnit, days: days)) ?? [:]
        let rhr = (try? await health.dailyAverage(.restingHeartRate, unit: .bpm, days: days)) ?? [:]
        let overnight = (try? await health.overnightAverages(.heartRateVariabilitySDNN, unit: .msUnit, sessions: main, days: days)) ?? [:]
        let useOvernight = overnight.count >= 5
        return HeartData(hrvByDay: useOvernight ? overnight : daily, dailyHRV: daily, rhrByDay: rhr, overnight: useOvernight,
                         excluded: baselineExclusions())
    }

    /// Her usual value before `day`: the median of the 30 days before it,
    /// leaving out `excluding` (calendar days), once there are at least 5
    /// (one odd day can't set it).
    static func baseline(_ byDay: [Date: Double], before day: Date, excluding: Set<Date> = [],
                         calendar: Calendar = .current) -> Double? {
        let xs = window(byDay, before: day, excluding: excluding, calendar: calendar)
        return xs.count >= 5 ? xs.median : nil
    }

    /// The values of the 30 days before `day` (the baseline window), less
    /// the days in `excluding`.
    static func window(_ byDay: [Date: Double], before day: Date, excluding: Set<Date> = [],
                       calendar: Calendar = .current) -> [Double] {
        guard let from = calendar.date(byAdding: .day, value: -30, to: day) else { return [] }
        return byDay.filter { $0.key < day && $0.key >= from && !excluding.contains(calendar.startOfDay(for: $0.key)) }.map(\.value)
    }

    func night(_ s: SleepSession, heart: HeartData) -> NightRecord {
        let day = Calendar.current.startOfDay(for: s.wake)
        var outcome = NextDayOutcome()
        if let v = heart.hrvByDay[day], let b = Self.baseline(heart.hrvByDay, before: day, excluding: heart.excluded), b > 0 { outcome.hrvDeltaPct = (v - b) / b * 100 }
        if let v = heart.rhrByDay[day], let b = Self.baseline(heart.rhrByDay, before: day, excluding: heart.excluded) { outcome.restingHRDelta = v - b }
        if let c = store.checkIn(forWakeDay: day) { outcome.checkIn = Double(c.awake) }
        return NightRecord(session: s, outcome: outcome)
    }

    /// Today's HRV and resting heart rate: today's reading, else yesterday's.
    /// Deltas only against a real baseline. Returns whether there was any.
    @discardableResult
    private func applyHeart(_ heart: HeartData) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let hrvDay = [today, yesterday].first { heart.hrvByDay[$0] != nil }
        let rhrDay = [today, yesterday].first { heart.rhrByDay[$0] != nil }
        if let d = hrvDay, let v = heart.hrvByDay[d] {
            hrv = v
            hrvDeltaPct = Self.baseline(heart.hrvByDay, before: d, excluding: heart.excluded).map { $0 > 0 ? (v - $0) / $0 * 100 : 0 } ?? 0
        } else {
            hrv = Self.baseline(heart.hrvByDay, before: today, excluding: heart.excluded) ?? 0
            hrvDeltaPct = 0
        }
        if let d = rhrDay, let v = heart.rhrByDay[d] {
            restingHR = v
            restingHRDelta = Self.baseline(heart.rhrByDay, before: d, excluding: heart.excluded).map { v - $0 } ?? 0
        } else {
            restingHR = Self.baseline(heart.rhrByDay, before: today, excluding: heart.excluded) ?? 0
            restingHRDelta = 0
        }
        restingHRBaselineKnown = Self.baseline(heart.rhrByDay, before: rhrDay ?? today, excluding: heart.excluded) != nil
        stressHRVBaseline = Self.baseline(heart.dailyHRV, before: today, excluding: heart.excluded)
        let rhrWindow = Self.window(heart.rhrByDay, before: rhrDay ?? today, excluding: heart.excluded)
        let hrvWindow = Self.window(heart.hrvByDay, before: hrvDay ?? today, excluding: heart.excluded)
        restingHRSpread = HeartBands.spread(rhrWindow)
        hrvSpreadPct = HeartBands.spread(hrvWindow).flatMap { sd in hrvWindow.median.flatMap { $0 > 0 ? sd / $0 * 100 : nil } }
        restingHRUsualRange = HeartBands.usualRange(rhrWindow)
        hrvUsualRange = HeartBands.usualRange(hrvWindow)
        hrvIsOvernight = heart.overnight
        hasHeartData = hrvDay != nil || rhrDay != nil
        return hasHeartData
    }

    /// Example nights with her real ones put in place of the example night
    /// for the same morning (the first 14 nights).
    static func merge(sample: [NightRecord], real: [NightRecord], calendar: Calendar = .current) -> [NightRecord] {
        let realDays = Set(real.map { calendar.startOfDay(for: $0.wakeDay) })
        return (sample.filter { !realDays.contains(calendar.startOfDay(for: $0.wakeDay)) } + real).sorted { $0.wakeDay < $1.wakeDay }
    }

    func isRealNight(_ night: NightRecord) -> Bool {
        realNightDays.contains(Calendar.current.startOfDay(for: night.wakeDay))
    }

    /// Nights the sleep need was learned from that are hers. During the
    /// example period that's her real nights so far (the need itself is
    /// still the example's: `sleepNeedIsExample`).
    var sleepNeedNightsUsed: Int { usingSampleData ? realNightCount : sleepNeed.nights }
    var sleepNeedIsExample: Bool { usingSampleData }

    func refresh() async throws {
        guard !loading else {
            // A refresh is already running; run once more after it, so a
            // change made meanwhile (a logged period) isn't lost.
            refreshAgain = true
            return
        }
        loading = true
        defer {
            loading = false
            if refreshAgain {
                refreshAgain = false
                Task { try? await self.refresh() }
            }
        }
        if prefersSampleData {
            applySampleData()
            recomputeCycle()
            finishRefresh()
            return
        }
        // Everything is read from Apple Health first and published after the
        // last read, with no awaits in between: each published change redraws
        // every screen, so changes spread across the reads redrew them dozens
        // of times a refresh and made scrolling and taps stutter.
        let cal = Calendar.current
        let days = 120
        let all = try await health.sleepSessions(days: days)
        let main = Self.mainSleeps(all)
        let fresh = Self.latestMainSleep(in: main, now: .now, appDayStart: appDayStart)
        let periods = (try? await health.periodStarts(days: 400)) ?? []
        let heart = await loadHeart(main: main, days: days)
        let built = main.map { night($0, heart: heart) }
        let healthCaffeine = (try? await health.logSamples(.dietaryCaffeine, unit: .gramUnit(with: .milli), days: Self.healthLogDays)) ?? []
        let healthWater = (try? await health.logSamples(.dietaryWater, unit: .literUnit(with: .milli), days: Self.healthLogDays)) ?? []

        guard main.count >= Self.nightsNeeded else {
            // Example data until 14 nights, but her own last night as soon as
            // there is one, her own nights in the history, her own heart
            // readings once there's a baseline, and her own cycle.
            realNightCount = main.count
            mergeHealthLogs(caffeine: healthCaffeine, water: healthWater)
            applySampleData()
            healthPeriodStarts = periods
            nights = Self.merge(sample: nights, real: built)
            realNightDays = Set(built.map { cal.startOfDay(for: $0.wakeDay) })
            if let fresh {
                lastNight = LastNight(session: fresh)
                lastNightIsReal = true
            }
            let sampleHeart = (hrv, restingHR, hrvDeltaPct, restingHRDelta, stressHRVBaseline)
            if applyHeart(heart), Self.baseline(heart.hrvByDay, before: cal.startOfDay(for: .now), excluding: heart.excluded) != nil || restingHRBaselineKnown {
                heartIsReal = true
            } else {
                (hrv, restingHR, hrvDeltaPct, restingHRDelta, stressHRVBaseline) = sampleHeart
                restingHRSpread = nil; hrvSpreadPct = nil
                hrvUsualRange = nil; restingHRUsualRange = nil
                hasHeartData = true
                restingHRBaselineKnown = true
                hrvIsOvernight = false
            }
            recomputeCycle()
            finishRefresh()
            return
        }

        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let daylight = (try? await health.dailySum(.timeInDaylight, unit: .minute(), days: 9)) ?? [:]
        let steps = (try? await health.dailySum(.stepCount, unit: .count(), days: 2)) ?? [:]
        let daylightHourly = (try? await health.hourlyToday(.timeInDaylight, unit: .minute(), sum: true)) ?? [:]
        // Stress, sickness signals, fitness and calories. Each is optional:
        // a missing permission or type just leaves "no data".
        let hrHourly = (try? await health.hourlyToday(.heartRate, unit: .bpm, sum: false)) ?? [:]
        let hrvHourly = (try? await health.hourlyToday(.heartRateVariabilitySDNN, unit: .msUnit, sum: false)) ?? [:]
        let stepsHourly = (try? await health.hourlyToday(.stepCount, unit: .count(), sum: true)) ?? [:]
        let kcalHourly = (try? await health.hourlyToday(.activeEnergyBurned, unit: .kilocalorie(), sum: true)) ?? [:]
        let mass = try? await health.latest(.bodyMass, unit: .gramUnit(with: .kilo), days: 365)
        let stillBaseline = await stillHourBaseline(sessions: all, bodyMassKg: mass)
        let respiratory = (try? await health.dailyAverage(.respiratoryRate, unit: .count().unitDivided(by: .minute()), days: 40)) ?? [:]
        let wristTemp = (try? await health.dailyAverage(.appleSleepingWristTemperature, unit: .degreeCelsius(), days: 40)) ?? [:]
        let vo2 = (try? await health.samples(.vo2Max, unit: .vo2, days: 5 * 365)) ?? []
        let activeByDay = (try? await health.dailySum(.activeEnergyBurned, unit: .kilocalorie(), days: 16)) ?? [:]
        let resting = ((try? await health.dailySum(.basalEnergyBurned, unit: .kilocalorie(), days: 1)) ?? [:])[today] ?? 0

        // From here to the end, no awaits: one redraw.
        if store.data.ageYears == nil, let age = health.ageYears(), (13...100).contains(age) { store.data.ageYears = age }
        realNightCount = main.count
        mergeHealthLogs(caffeine: healthCaffeine, water: healthWater)
        usingSampleData = false
        self.sessions = main
        nights = built
        realNightDays = Set(built.map { cal.startOfDay(for: $0.wakeDay) })
        mornings = built.compactMap { n in
            guard let felt = n.outcome.checkIn else { return nil }
            return Morning(wake: n.wake, wokeFromLightSleep: n.wokeFromLightSleep, outcome: felt)
        }
        // Last night: the longest sleep that ended during this app day or the
        // evening before, so a nap never replaces it. Otherwise keep the
        // latest night but say so.
        if let night = fresh ?? main.last { lastNight = LastNight(session: night) }
        lastNightIsFresh = fresh != nil
        lastNightIsReal = true

        applyHeart(heart)
        heartIsReal = hasHeartData

        daylightByDay = daylight
        daylightToday = Int(daylight[today] ?? 0)
        morningDaylightToday = Self.morningDaylight(daylightHourly)
        stepsToday = Int(steps[today] ?? 0)
        healthPeriodStarts = periods
        recomputeCycle()
        workNights = built.filter(\.alarmUsed).map { Chronotype.Night(onset: $0.sleepOnset, wake: $0.wake) }
        freeNights = built.filter { !$0.alarmUsed }.map { Chronotype.Night(onset: $0.sleepOnset, wake: $0.wake) }
        chronotypeIsLearning = workNights.isEmpty || freeNights.isEmpty

        bodyMassKg = mass
        stressStillBaseline = stillBaseline
        let asleepSegments = all.filter { $0.wake > today }.flatMap(\.segments).filter { $0.stage != .awake }
        func asleep(inHour h: Int) -> Bool {
            guard let a = cal.date(bySettingHour: h, minute: 0, second: 0, of: today) else { return false }
            let b = a.addingTimeInterval(3600)
            let overlap = asleepSegments.reduce(0.0) { $0 + max(0, min($1.end, b).timeIntervalSince(max($1.start, a))) }
            return overlap >= 1800
        }
        let nowHour = cal.component(.hour, from: .now)
        stressSamples = (0...nowHour).map { h in
            StressModel.Sample(hour: h, heartRate: hrHourly[h], hrv: hrvHourly[h], steps: stepsHourly[h] ?? 0,
                               activeKcal: kcalHourly[h] ?? 0, asleep: asleep(inHour: h))
        }
        func delta(_ byDay: [Date: Double]) -> Double? {
            guard let v = byDay[today] ?? byDay[yesterday], let b = Self.baseline(byDay, before: today, excluding: heart.excluded) else { return nil }
            return v - b
        }
        respiratoryRateDelta = delta(respiratory)
        wristTempDelta = delta(wristTemp)
        vo2Max = vo2.last?.value
        vo2MaxHistory = vo2
        activeCalories = activeByDay[today] ?? 0
        activeCaloriesYesterday = activeByDay[yesterday]
        activeCaloriesEarlier = activeByDay.filter { $0.key < yesterday }.map(\.value)
        restingCalories = resting

        lastWeek = buildLastWeek(daylight: daylight)
        updatePersonalUsuals()
        finishRefresh()
    }

    /// Her heart rate in still, awake hours over the 14 days before today:
    /// hours with few steps and little active energy (her own active-hour
    /// threshold), not the hour after an active one, and not mostly asleep.
    /// Nil until there are enough such hours (`StressModel.stillHoursNeeded`).
    private func stillHourBaseline(sessions: [SleepSession], bodyMassKg: Double?, days: Int = 14) async -> StressModel.StillBaseline? {
        let hr = (try? await health.hourly(.heartRate, unit: .bpm, sum: false, days: days)) ?? [:]
        guard hr.count >= StressModel.stillHoursNeeded else { return nil }
        let steps = (try? await health.hourly(.stepCount, unit: .count(), sum: true, days: days)) ?? [:]
        let kcal = (try? await health.hourly(.activeEnergyBurned, unit: .kilocalorie(), sum: true, days: days)) ?? [:]
        let activeKcal = StressModel.activeKcal(bodyMassKg: bodyMassKg)
        func active(_ h: Date) -> Bool { (steps[h] ?? 0) > StressModel.activeSteps || (kcal[h] ?? 0) >= activeKcal }
        let from = Calendar.current.date(byAdding: .day, value: -(days + 1), to: .now) ?? .distantPast
        let asleep = sessions.filter { $0.wake > from }.flatMap(\.segments).filter { $0.stage != .awake }
        let still = hr.compactMap { hour, bpm -> Double? in
            let end = hour.addingTimeInterval(3600)
            guard !active(hour), !active(hour.addingTimeInterval(-3600)) else { return nil }
            let slept = asleep.reduce(0.0) { $0 + max(0, min($1.end, end).timeIntervalSince(max($1.start, hour))) }
            return slept >= 1800 ? nil : bpm
        }
        return StressModel.stillBaseline(heartRates: still)
    }

    /// Cycle day and length from Apple Health's period starts plus the
    /// bleeds logged in the app, by the calendar day. Runs on every refresh
    /// and whenever she logs or edits a bleed (also with example data), so
    /// a logged period shows up straight away.
    func recomputeCycle() {
        let cal = Calendar.current
        let starts = Self.mergedPeriodStarts(health: healthPeriodStarts, logged: store.data.flowLog)
        // Only cycles since her last birth-control change set her usual length.
        let lengths = CycleEstimator.lengths(periodStarts: starts, since: store.data.methodChangedDate)
        cycleLengthsRunLong = lengths.runLong
        personalCycleLength = lengths.usual
        if let last = starts.last {
            cycleDay = (cal.dateComponents([.day], from: last, to: cal.startOfDay(for: .now)).day ?? 0) + 1
            cycleLength = lengths.usual ?? Self.typicalCycleLength
        } else {
            // No period logged: no cycle day, even while the rest is example
            // data. A made-up cycle would put a period on her calendar.
            cycleDay = nil
            cycleLength = Self.typicalCycleLength
        }
    }

    private func finishRefresh() {
        lastRefreshed = .now
        if let o = store.data.alarmOverride, AppDay.date(o.end, relativeTo: o.wakeDay) <= .now {
            store.data.alarmOverride = nil   // that morning has passed
        }
        applyExamCrunch()
        pushToWatch()
        Task {
            await updateHealthConnection()
            await updateNudges()
            await updatePill()
            await updateHealthMood()
        }
    }

    /// Each wake day's main sleep: the longest session that ended that day.
    static func mainSleeps(_ sessions: [SleepSession], calendar: Calendar = .current) -> [SleepSession] {
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.wake) }
        return byDay.values.compactMap { $0.max { $0.asleepMinutes < $1.asleepMinutes } }.sorted { $0.wake < $1.wake }
    }

    /// Last night: the longest sleep that ended after the evening before
    /// this app day began (its rollover minus 12 hours) and by now. So at
    /// 2am, before the rollover, yesterday morning's wake still counts; it
    /// only goes stale once the next app day starts.
    static func latestMainSleep(in sessions: [SleepSession], now: Date, appDayStart: Date? = nil) -> SleepSession? {
        let from = (appDayStart ?? AppDay.start(containing: now)).addingTimeInterval(-12 * 3600)
        return sessions.filter { $0.wake <= now && $0.wake >= from }.max { $0.asleepMinutes < $1.asleepMinutes }
    }

    /// The seven days before today, from her real nights, logged caffeine and
    /// daylight. Days without a night are left out.
    func buildLastWeek(daylight: [Date: Double]) -> [DaySummary] {
        let cal = Calendar.current
        let newestFirst = nights.sorted { $0.wakeDay > $1.wakeDay }
        return (1...7).reversed().compactMap { back -> DaySummary? in
            guard let day = cal.date(byAdding: .day, value: -back, to: appDayDate),
                  let n = newestFirst.first(where: { cal.isDate($0.wakeDay, inSameDayAs: day) }) else { return nil }
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            let drinks = store.data.drinkLog.filter { AppDay.contains($0.date, now: noon) }
            return DaySummary(date: day, energy: energyScore(for: n), asleep: n.asleepMinutes,
                              bedtime: n.bedtime, wake: n.wake, wokeFromLightSleep: n.wokeFromLightSleep ?? false,
                              daylightMinutes: Int(daylight[day] ?? 0), caffeineMg: drinks.map(\.mg).reduce(0, +),
                              lastCaffeine: drinks.map { AppDay.minutes($0.date, relativeTo: day) }.max(),
                              checkIn: store.checkIn(forWakeDay: day).map { Double($0.awake) })
        }
    }

    /// Her own usual recovery and energy: averages over the last 30 nights
    /// before today's (recovery needs heart data), once there are at least
    /// 7. Today's own night is left out, so "usual" never includes today.
    /// With 14+ recovery days, also how much her score usually moves.
    private func updatePersonalUsuals() {
        let need = sleepNeed.minutes
        let today = lastNightWakeDay
        let earlier = nights.filter { $0.wakeDay < today }.sorted { $0.wakeDay > $1.wakeDay }
        let recent = Array(earlier.prefix(30))
        let recoveries: [Double] = recent
            .filter { $0.outcome.hrvDeltaPct != nil || $0.outcome.restingHRDelta != nil }
            .map { n in
                Double(Recovery.score(usual: Double(Self.recoveryAnchor), hrvDeltaPct: n.outcome.hrvDeltaPct ?? 0,
                                      restingHRDelta: n.outcome.restingHRDelta ?? 0,
                                      sleepShortfall: max(0, need - n.asleepMinutes - 15),
                                      cycle: cycleHeartShift(on: n.wakeDay)))
            }
        personalRecoveryUsual = recoveries.count >= 7 ? recoveries.mean.map { Int($0.rounded()) } : nil
        recoveryDaysLearned = recoveries.count
        personalRecoverySpread = recoveries.count >= 14 ? recoveries.standardDeviation : nil
        let energies: [Double] = recent.prefix(14).map { Double(energyScore(for: $0)) }
        personalEnergyUsual = energies.count >= 7 ? energies.mean.map { Int($0.rounded()) } : nil
    }

    // MARK: Logs from Apple Health

    /// How far back caffeine and water are read in from Apple Health.
    static let healthLogDays = 60
    /// The drink id for caffeine read in from Health that matches none of
    /// her drinks by name.
    static let healthCaffeineDrinkID = UUID(uuidString: "6E0C2A51-3F0B-4D8E-9C1A-0D5B2E7F4A10")!

    /// Adds caffeine and water saved in Apple Health that the app's own log
    /// doesn't have: what the old Health Dashboard logged (it kept its logs
    /// only in Health), Shortcuts, other apps. Entries this app saved carry
    /// its id and are skipped, and so are ones she deleted here.
    func mergeHealthLogs(caffeine: [HealthLogSample], water: [HealthLogSample]) {
        var data = store.data
        let removed = data.removedHealthLogIDs
        var drinkIDs = Set(data.drinkLog.map(\.id)).union(removed)
        for s in caffeine {
            let id = s.appID ?? s.id
            guard !drinkIDs.contains(id), !drinkIDs.contains(s.id) else { continue }
            let mg = Int(s.value.rounded())
            guard mg > 0 else { continue }
            let name = s.name ?? "Caffeine"
            let drinkID = (data.savedDrinks + Drink.common).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
                ?? Self.healthCaffeineDrinkID
            data.drinkLog.append(AppData.LoggedDrink(id: id, drinkID: drinkID, name: name, mg: mg, date: s.date))
            drinkIDs.insert(id)
        }
        var waterIDs = Set(data.waterLog.map(\.id)).union(removed)
        for s in water {
            let id = s.appID ?? s.id
            guard !waterIDs.contains(id), !waterIDs.contains(s.id), s.value > 0 else { continue }
            data.waterLog.append(AppData.WaterEntry(id: id, date: s.date, ml: s.value))
            waterIDs.insert(id)
        }
        guard data.drinkLog.count != store.data.drinkLog.count || data.waterLog.count != store.data.waterLog.count else { return }
        data.drinkLog.sort { $0.date < $1.date }
        data.waterLog.sort { $0.date < $1.date }
        store.data = data
    }

    // MARK: Actions

    /// Log a drink. The time is never in the future: a clock time picked
    /// after midnight for the evening before lands on that evening.
    /// Everything is saved to Apple Health, also while the app shows example
    /// data.
    func log(_ drink: Drink, at date: Date = .now, saveToHealth: Bool = true) {
        logDrink(id: UUID(), drinkID: drink.id, name: drink.name, mg: drink.caffeineMg, at: date, saveToHealth: saveToHealth)
    }

    func logDrink(id: UUID, drinkID: UUID, name: String, mg: Int, at date: Date, saveToHealth: Bool) {
        guard !store.data.drinkLog.contains(where: { $0.id == id }) else { return }
        var entry = AppData.LoggedDrink(drinkID: drinkID, name: name, mg: mg, date: AppDay.pastTime(date))
        entry.id = id
        store.data.drinkLog.append(entry)
        if saveToHealth {
            let e = entry
            writeHealth { try await $0.saveCaffeine(mg: e.mg, at: e.date, id: e.id) }
        }
        pushToWatch()
    }

    /// Change the time or amount of a logged drink. A time-only change stays
    /// on the drink's own day; it can't move into the future.
    func updateDrink(_ id: UUID, date: Date, mg: Int) {
        guard let i = store.data.drinkLog.firstIndex(where: { $0.id == id }) else { return }
        let when = AppDay.editedTime(date, original: store.data.drinkLog[i].date)
        store.data.drinkLog[i].date = when
        store.data.drinkLog[i].mg = mg
        let entry = store.data.drinkLog[i]
        writeHealth { health in
            try await health.deleteCaffeine(id: entry.id)
            try await health.saveCaffeine(mg: entry.mg, at: entry.date, id: entry.id)
        }
        pushToWatch()
    }

    func deleteDrink(_ id: UUID) {
        guard store.data.drinkLog.contains(where: { $0.id == id }) else { return }
        store.data.drinkLog.removeAll { $0.id == id }
        store.data.removedHealthLogIDs.insert(id)
        writeHealth { try await $0.deleteCaffeine(id: id) }
        pushToWatch()
    }

    func save(customDrink: Drink, logNow: Bool) {
        var d = customDrink
        d.isCustom = true
        store.data.savedDrinks.append(d)
        if logNow { log(d) }
        pushToWatch()
    }

    /// Log water: a fraction of your bottle (default one whole bottle).
    func addWater(bottles: Double = 1, at date: Date = .now) {
        addWater(ml: store.data.bottleSizeML * bottles, at: date)
    }

    /// `id`: the entry's own id, e.g. one the Watch made, so it's never
    /// added twice and can be undone from the Watch.
    /// `saveToHealth`: false when it's in Apple Health already (a widget saved it).
    func addWater(ml: Double, at date: Date = .now, id: UUID = UUID(), saveToHealth: Bool = true) {
        guard !store.data.waterLog.contains(where: { $0.id == id }) else { return }
        var entry = AppData.WaterEntry(date: AppDay.pastTime(date), ml: ml)
        entry.id = id
        store.data.waterLog.append(entry)
        guard saveToHealth else { return }
        writeHealth { try await $0.saveWater(ml: entry.ml, at: entry.date, id: entry.id) }
    }

    func updateWater(_ id: UUID, date: Date, ml: Double) {
        guard let i = store.data.waterLog.firstIndex(where: { $0.id == id }) else { return }
        store.data.waterLog[i].date = AppDay.editedTime(date, original: store.data.waterLog[i].date)
        store.data.waterLog[i].ml = ml
        let entry = store.data.waterLog[i]
        writeHealth { health in
            try await health.deleteWater(id: entry.id)
            try await health.saveWater(ml: entry.ml, at: entry.date, id: entry.id)
        }
    }

    func deleteWater(_ id: UUID) {
        guard store.data.waterLog.contains(where: { $0.id == id }) else { return }
        store.data.waterLog.removeAll { $0.id == id }
        store.data.removedHealthLogIDs.insert(id)
        writeHealth { try await $0.deleteWater(id: id) }
    }

    /// Runs an Apple Health write in the background and records whether it
    /// worked. The app's own log is kept either way.
    private func writeHealth(_ work: @escaping (HealthKitService) async throws -> Void) {
        guard HealthKitService.isAvailable, !DemoMode.isOn else { return }
        let health = self.health
        Task {
            do {
                try await work(health)
                healthWriteFailed = false
            } catch {
                healthWriteFailed = true
            }
        }
    }

    /// Saves this app day's morning check-in (replacing one already done
    /// today). Between midnight and the rollover there's no morning to check
    /// in on (`canCheckInNow` is false).
    func saveCheckIn(awake: Int, tags: [String]) {
        let today = AppDay.day()
        store.data.checkIns.removeAll { Calendar.current.isDate(AppDay.day(containing: $0.date), inSameDayAs: today) }
        store.data.checkIns.append(.init(date: .now, awake: awake, tags: tags))
    }

    /// This app day's check-in is done.
    var checkInDoneToday: Bool { store.checkIn(on: .now) != nil }
    /// The morning check-in makes sense now: not between midnight and the
    /// rollover (that's still last night).
    var canCheckInNow: Bool { !AppDay.isBeforeRollover() }

    /// Turns the smart alarm on with tonight's planned window. Replaces any
    /// one-off window set for that morning.
    func setSmartAlarm(from plan: WakePlan) {
        store.data.alarmOverride = nil
        store.data.smartAlarmEnabled = true
        pushToWatch()
    }

    // MARK: Settings changes

    private func storeDidChange(from old: AppData, to new: AppData) {
        if old.bedtime != new.bedtime {
            AppDay.rolloverMinutes = AppDay.rollover(forBedtime: new.bedtime)
        }
        let planRelevant = old.bedtime != new.bedtime || old.upBy != new.upBy
            || old.smartAlarmEnabled != new.smartAlarmEnabled || old.alarmWeekdaysOnly != new.alarmWeekdaysOnly
            || old.sleepNeedAdjustment != new.sleepNeedAdjustment || old.phoneBackupAlarm != new.phoneBackupAlarm
        let watchRelevant = planRelevant || old.savedDrinks != new.savedDrinks
            || old.birthControl != new.birthControl || old.cycleSetup != new.cycleSetup
            || old.moodRatings != new.moodRatings
            // Today's pill on the widgets and the Watch.
            || old.pillsTaken != new.pillsTaken || old.pillTime != new.pillTime
        // (alarmOverride is written by pushToWatch itself, which then sends.)
        if watchRelevant {
            pushToWatch()
        } else if old.waterLog != new.waterLog || old.drinkLog != new.drinkLog || old.flowLog != new.flowLog
                    || old.packStartDate != new.packStartDate || old.bottleSizeML != new.bottleSizeML
                    || old.waterGoalML != new.waterGoalML || old.hotDay != new.hotDay || old.conditions != new.conditions
                    || old.moodLog != new.moodLog {
            // Widgets show today's water, caffeine and cycle (and hide the
            // water goal with an eating-disorder history).
            Task { @MainActor in self.publishWidgetSnapshot() }
        }
        if planRelevant || old.alarmOverride != new.alarmOverride { Task { await updateAlarmNudge() } }

        // A logged or edited bleed moves the cycle day straight away.
        if old.flowLog != new.flowLog { recomputeCycle() }

        if new.savesCycleToHealth, !old.savesCycleToHealth || old.flowLog != new.flowLog || old.symptomLog != new.symptomLog
            || old.birthControl != new.birthControl || old.methodChangedDate != new.methodChangedDate {
            Task { await syncCycleToHealth() }
        }

        if Self.pillRelevantChange(old, new) { Task { await updatePill(readHealth: old.pillReadsHealth != new.pillReadsHealth) } }

        // A new method: the old pack type and start don't carry over.
        let oldMethod = old.cycleSetup == .hormonal ? old.birthControl : nil
        let newMethod = new.cycleSetup == .hormonal ? new.birthControl : nil
        if oldMethod != newMethod {
            let startChangedToo = old.packStartDate != new.packStartDate
            // A save that sets the change date itself (example data) keeps it.
            let dateSetToo = old.methodChangedDate != new.methodChangedDate
            Task { @MainActor in
                self.normalizePack(keepStart: startChangedToo)
                // Cycles before the change don't set her natural length.
                if !dateSetToo { self.store.data.methodChangedDate = Calendar.current.startOfDay(for: .now) }
                self.recomputeCycle()
            }
        }

        // Starting over (Delete all data): Apple Health again, not the example.
        if old.onboarded && !new.onboarded && prefersSampleData { setPrefersSampleData(false) }

        // Clock-change reminders follow the plan they were made from.
        if new.timeChangeReminders, old.bedtime != new.bedtime || old.upBy != new.upBy
            || old.timeChangeStrategy != new.timeChangeStrategy || old.sleepNeedAdjustment != new.sleepNeedAdjustment {
            Task { await rescheduleTimeChangeReminders() }
        }

        let turnedOn = (new.peakDipNudges && !old.peakDipNudges) || (new.sickAlerts && !old.sickAlerts)
        let finishedSetup = new.onboarded && !old.onboarded && (new.peakDipNudges || new.sickAlerts || new.insights.morningNote)
        if turnedOn || finishedSetup {
            Task {
                await Nudges.requestPermission()
                await updateNudges()
            }
        } else if old.peakDipNudges && !new.peakDipNudges {
            Task { await Nudges.cancelPeakDip() }
        } else if new.peakDipNudges && (old.bedtime != new.bedtime || old.upBy != new.upBy) {
            Task { await updateNudges() }
        }
    }

    /// Pack settings that fit the method: 24+4 is a pill pack only (ring and
    /// patch are 21+7 or continuous), every pack is 28 days, and the pack
    /// start from another method is cleared unless she just set a new one.
    private func normalizePack(keepStart: Bool) {
        let valid: Set<Int> = store.birthControl == .combinedPill ? [21, 24, 28] : [21, 28]
        if !valid.contains(store.data.packActiveDays) { store.data.packActiveDays = 21 }
        if store.data.packLength != 28 { store.data.packLength = 28 }
        if !keepStart && store.data.packStartDate != nil { store.data.packStartDate = nil }
        if store.data.packCheckDismissed != nil { store.data.packCheckDismissed = nil }
    }

    /// Re-schedules the clock-change bedtime reminders from the current
    /// bedtime, wake time and saved plan.
    func rescheduleTimeChangeReminders() async {
        guard store.data.timeChangeReminders else { await BedtimeReminders.cancelAll(); return }
        let nights = timeChangeNights(timeChangeStrategy(explicitlyChosen: true))
        let reminders = BedtimeReminders.timeChangeReminders(nights: nights, nightDate: { self.timeChangeNightDate(offset: $0) })
        _ = await BedtimeReminders.schedule(reminders)
    }

    /// Reschedules the peak/dip nudges (the rest of today's, and tomorrow's
    /// from tonight's plan) and the sick alert. Today's need a real last
    /// night (zones from example data would be made up).
    func updateNudges() async {
        if store.data.peakDipNudges, lastNightIsReal {
            var plans: [Nudges.Plan] = []
            if lastNightIsFresh {
                plans += Nudges.peakDipPlan(zones: energyToday.zones, appDay: appDayDate)
            }
            plans += Nudges.peakDipPlan(zones: energyTomorrow.zones, appDay: nextWakeDay, tag: "tomorrow-")
            await Nudges.reschedulePeakDip(plans)
        } else {
            await Nudges.cancelPeakDip()
        }
        if store.data.sickAlerts, !usingSampleData, hasHeartData {
            let signal = illness
            await Nudges.sickAlertIfNeeded(signal.confidence, cyclePhaseUnknown: signal.cyclePhaseUnknown)
        }
        await updateAlarmNudge()
        await updateBedtimeNudge()
        await updateMorningNote()
    }

    // MARK: Smart alarm on the Watch

    private static let armedEndKey = "watch.armedAlarmEnd"
    private static let watchReportsKey = "watch.reportsAlarm"
    private static let watchOffKey = "watch.alarmOffOnWatch"

    /// The next morning the smart alarm rings, with its window as dates:
    /// a one-off (exam) window, else tonight's plan on the next morning
    /// that isn't skipped (weekends with "weekdays only").
    var nextAlarmWindow: (wakeDay: Date, start: Date, end: Date)? {
        guard store.data.smartAlarmEnabled else { return nil }
        if let o = activeAlarmOverride {
            return (o.wakeDay, AppDay.date(o.start, relativeTo: o.wakeDay), AppDay.date(o.end, relativeTo: o.wakeDay))
        }
        guard let w = wakePlan()?.alarmWindow else { return nil }
        let cal = Calendar.current
        for i in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: i, to: nextWakeDay) else { break }
            if store.data.alarmWeekdaysOnly && cal.isDateInWeekend(day) { continue }
            let end = AppDay.date(w.end, relativeTo: day)
            guard end > .now else { continue }
            return (day, AppDay.date(w.start, relativeTo: day), end)
        }
        return nil
    }

    /// The Watch says the next alarm is on (it reported the same latest time).
    var watchAlarmIsOn: Bool {
        guard let next = nextAlarmWindow,
              let armed = UserDefaults.standard.object(forKey: Self.armedEndKey) as? Double else { return false }
        return abs(Date(timeIntervalSinceReferenceDate: armed).timeIntervalSince(next.end)) < 120
    }

    /// The Watch can only turn the alarm on while its app is open, at most 36
    /// hours ahead. When the next alarm isn't on (the Watch says so, or
    /// it follows a skipped weekend), a phone notification the evening
    /// before, an hour before bedtime, asks her to open the Watch app.
    func updateAlarmNudge() async {
        let defaults = UserDefaults.standard
        guard let next = nextAlarmWindow, !defaults.bool(forKey: Self.watchOffKey) else {
            await Nudges.cancelAlarmArm()
            return
        }
        if let armed = defaults.object(forKey: Self.armedEndKey) as? Double,
           abs(Date(timeIntervalSinceReferenceDate: armed).timeIntervalSince(next.end)) < 120 {
            await Nudges.cancelAlarmArm()
            return
        }
        let cal = Calendar.current
        let afterSkippedDay = store.data.alarmWeekdaysOnly && activeAlarmOverride == nil
            && (cal.date(byAdding: .day, value: -1, to: next.wakeDay).map(cal.isDateInWeekend) ?? false)
        guard defaults.bool(forKey: Self.watchReportsKey) || afterSkippedDay else {
            await Nudges.cancelAlarmArm()
            return
        }
        let fire = AppDay.date(tonightBedtime - 60, relativeTo: next.wakeDay)
        guard fire > .now, fire < next.start else {
            await Nudges.cancelAlarmArm()
            return
        }
        await Nudges.scheduleAlarmArm(at: fire, wakeTime: next.end)
    }

    // MARK: Watch

    /// The morning a window ending at `end` belongs to: today if that time is
    /// still ahead, else tomorrow.
    static func wakeDay(forWindowEnding end: Minutes, now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        if AppDay.date(end, relativeTo: today, calendar: calendar) > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// Sends the latest numbers and the alarm window to the Watch. `alarm` is
    /// a one-off window for one morning (exam mode); it's kept until that
    /// morning has passed, so later pushes don't overwrite it.
    func pushToWatch(alarm: TimeRange? = nil, wakeDay: Date? = nil) {
        // Widgets and complications get the same moment's numbers, and the
        // iPhone backup alarm follows the same window.
        publishWidgetSnapshot()
        updatePhoneBackupAlarm()
        updateBedtimeActivity()
        let cal = Calendar.current
        if let alarm {
            let day = wakeDay.map { cal.startOfDay(for: $0) } ?? Self.wakeDay(forWindowEnding: alarm.end)
            store.data.alarmOverride = .init(wakeDay: day, start: alarm.start, end: alarm.end)
        }
        let override = activeAlarmOverride
        let windowDay = override?.wakeDay ?? nextWakeDay
        let window = override?.window ?? wakePlan()?.alarmWindow
        let today = appDayDate
        let t = now
        let energy = energyToday
        let current = energy.zones.first { $0.range.contains(t) }
        let next = energy.zones.first { $0.range.start > t }
        let curve = stride(from: 0, to: energy.curve.count, by: 3).map { energy.curve[$0].level }
        let shownRecovery = recoveryShown
        let cutoffBeforeWake = caffeineCutoffBeforeWake
        let tonight = tonightPlan
        WatchSync.shared.send(WatchSnapshot(
            recovery: shownRecovery ?? 0, recoveryLabel: recoveryLabel,
            energyNow: Int(energyBankNow.rounded()),
            energyZoneTitle: current?.title ?? "", nextZoneTitle: next?.title ?? "",
            nextZoneStart: next.map { AppDay.date($0.range.start, relativeTo: today) },
            bedtime: AppDay.date(tonightBedtime, relativeTo: nextWakeDay),
            alarmWindowStart: window.map { AppDay.date($0.start, relativeTo: windowDay) },
            alarmWindowEnd: window.map { AppDay.date($0.end, relativeTo: windowDay) },
            alarmEnabled: store.data.smartAlarmEnabled,
            caffeineTodayMg: caffeineMgToday,
            caffeineCutoff: cutoffBeforeWake ? nil : AppDay.date(caffeineCutoff, relativeTo: today),
            quickDrinks: store.data.savedDrinks.map { .init(id: $0.id, name: $0.name, caffeineMg: $0.caffeineMg) },
            energyCurve: curve,
            energyCurveStart: energy.curve.first.map { AppDay.date($0.time, relativeTo: today) },
            energyZones: energy.zones.map { .init(title: $0.title, start: AppDay.date($0.range.start, relativeTo: today),
                                                  end: AppDay.date($0.range.end, relativeTo: today), kind: $0.kind.rawValue) },
            energyZoneKind: current?.kind.rawValue,
            nextZoneKind: next?.kind.rawValue,
            // When the numbers were read, not when they were sent: stale data
            // stays marked stale on the Watch. Never refreshed (no Apple
            // Health on this device): the example is as of now.
            syncedAt: lastRefreshed ?? (HealthKitService.isAvailable && !DemoMode.isOn ? nil : .now),
            isSample: usingSampleData,
            alarmWeekdaysOnly: store.data.alarmWeekdaysOnly,
            alarmOneOff: override != nil,
            recoveryMissing: shownRecovery == nil,
            lastNightMissing: !lastNightIsFresh,
            todayDrinkIDs: todaysDrinks.map(\.id),
            caffeineCutoffBeforeWake: cutoffBeforeWake,
            plannedWake: tonight.wake.map { AppDay.date($0, relativeTo: nextWakeDay) },
            upBy: AppDay.date(tonight.upBy, relativeTo: nextWakeDay),
            tonightNeedMinutes: tonight.need,
            plannedAsleepMinutes: tonight.plan == nil ? nil : tonight.expectedAsleep,
            caffeineTooMuchAtBedtime: caffeineTooMuchAtBedtime,
            waterTodayML: waterTodayML,
            // No goal on the Watch under eating-disorder history: total only.
            waterGoalML: hidesActivityNumbers ? nil : waterGoalTodayML,
            bottleML: store.data.bottleSizeML,
            todayWaterIDs: todaysWater.map(\.id),
            stressHighAt: stressHighNow,
            moodToday: Dictionary(uniqueKeysWithValues: moodToday.map { ($0.key.rawValue, $0.value) }),
            morningLightMinutes: showsMorningLight ? morningDaylightToday : nil,
            morningLightGoal: Self.morningLightGoal))
    }

    func handle(_ message: WatchMessage) {
        switch message {
        case let .loggedDrink(id, at):
            // Older Watch builds: the saved drink and the tap time.
            if let d = store.data.savedDrinks.first(where: { $0.id == id }) { log(d, at: at) }
        case let .loggedDrinkEntry(entryID, drinkID, name, mg, at):
            // The phone saves it to Apple Health, once, under the Watch's id.
            logDrink(id: entryID, drinkID: drinkID, name: name, mg: mg, at: at, saveToHealth: true)
        case let .undoDrink(entryID):
            deleteDrink(entryID)
        case let .loggedWater(entryID, ml, at):
            addWater(ml: ml, at: at, id: entryID)
            pushToWatch()
        case let .undoWater(entryID):
            deleteWater(entryID)
            pushToWatch()
        case let .woke(at, _):
            // She stopped the Watch's alarm: this morning's backup isn't needed.
            PhoneBackupAlarm.shared.watchRang(at: at)
            // Pick the night up from Apple Health (fails quietly while locked).
            Task {
                if prefersSampleData { pushToWatch() } else { await syncWithHealth() }
            }
        case let .loggedMood(entryID, scale, value, at):
            if let scale = MoodScale(rawValue: scale) { logMood(scale, value, at: at, id: entryID) }
            pushToWatch()
        case let .undoMood(entryID):
            removeMood(entryID)
            pushToWatch()
        case let .alarmArmed(end, offOnWatch):
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: Self.watchReportsKey)
            defaults.set(offOnWatch, forKey: Self.watchOffKey)
            if let end {
                defaults.set(end.timeIntervalSinceReferenceDate, forKey: Self.armedEndKey)
            } else {
                defaults.removeObject(forKey: Self.armedEndKey)
            }
            Task { await updateAlarmNudge() }
            // "Watch alarm on" on the bedtime Live Activity.
            updateBedtimeActivity()
        case let .pillTaken(at):
            markPillTaken(at: at)
        case let .undoPill(at):
            unmarkPillTaken(on: pillDay(for: at))
        }
    }
}

extension AppModel.LastNight {
    /// Times relative to midnight of the app day she woke in (the same axis
    /// as `AppModel.now`), so "hours awake" is right even for a wake before
    /// the rollover.
    init(session: SleepSession, calendar: Calendar = .current) {
        let day = AppDay.day(containing: session.wake, calendar: calendar)
        var stages: [SleepStage: Int] = [:]
        for stage in SleepStage.allCases { stages[stage] = session.minutes(in: stage) }
        // Awake while asleep only: lying awake before falling asleep isn't
        // part of the night between "fell asleep" and "woke up".
        stages[.awake] = session.awakeAfterOnsetMinutes
        self.init(bedtime: AppDay.minutes(session.inBed, relativeTo: day, calendar: calendar),
                  onset: AppDay.minutes(session.sleepOnset, relativeTo: day, calendar: calendar),
                  wake: AppDay.minutes(session.wake, relativeTo: day, calendar: calendar),
                  asleep: session.asleepMinutes,
                  wokeFromLight: session.wokeFromLightSleep ?? true, stageMinutes: stages, segments: session.segments,
                  wakeDate: session.wake)
    }
}

extension AppModel {
    /// Period starts from Apple Health plus the ones logged in the app.
    /// A logged bleeding day starts a period when the two days before had none.
    static func mergedPeriodStarts(health: [Date], logged: [AppData.FlowEntry]) -> [Date] {
        let cal = Calendar.current
        let bleedDays = Set(logged.filter { $0.flow != .none && $0.flow != .spotting }.map { cal.startOfDay(for: $0.date) })
        // A new period starts after at least two bleed-free days.
        let loggedStarts = bleedDays.filter { day in
            !(1...2).contains { back in cal.date(byAdding: .day, value: -back, to: day).map(bleedDays.contains) ?? false }
        }
        var out: [Date] = []
        for d in (health.map { cal.startOfDay(for: $0) } + loggedStarts).sorted() {
            // Treat starts within a week of each other as the same period.
            if let prev = out.last, (cal.dateComponents([.day], from: prev, to: d).day ?? 99) < 7 { continue }
            out.append(d)
        }
        return out
    }
}
