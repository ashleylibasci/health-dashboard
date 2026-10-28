import Foundation
import Combine
import HealthCore

/// Things the app records itself (Apple Health has no place for them),
/// saved as JSON in Application Support. Stays on the phone.
///
/// Decoding is forgiving: any field missing from an older save falls back to
/// its default, so updates never wipe your settings or logs.
struct AppData: Codable {
    struct CheckIn: Codable, Hashable {
        var date: Date
        /// How awake, 1–5.
        var awake: Int
        var tags: [String]
    }
    struct LoggedDrink: Codable, Hashable, Identifiable {
        var id = UUID()
        var drinkID: UUID
        var name: String
        var mg: Int
        var date: Date
    }
    struct WaterEntry: Codable, Hashable, Identifiable {
        var id = UUID()
        var date: Date
        var ml: Double
    }
    struct AlcoholEntry: Codable, Hashable, Identifiable {
        var id = UUID()
        var date: Date
        var kind: String       // "Wine", "Beer", "Seltzer", "Cocktail", "Shot"
        var count: Int
    }
    enum Flow: String, Codable, CaseIterable { case none = "No flow", spotting = "Spotting", light = "Light", medium = "Medium", heavy = "Heavy" }
    struct FlowEntry: Codable, Hashable, Identifiable {
        var id = UUID()
        var date: Date
        var flow: Flow
    }
    struct SymptomEntry: Codable, Hashable, Identifiable {
        var id = UUID()
        var date: Date
        var symptoms: [String]
    }
    struct MoodEntry: Codable, Hashable, Identifiable {
        var id = UUID()
        var date: Date
        /// How stressed you felt, 1 (calm) – 5 (very stressed).
        var stress: Int
    }
    enum CycleSetup: String, Codable, CaseIterable { case natural, hormonal, irregular, notTracking }
    struct Exam: Codable, Hashable, Identifiable {
        var id = UUID()
        var title: String
        /// "Midterm", "Final", "Quiz"…
        var kind: String
        /// The exam day.
        var date: Date
        /// Start time, minutes after midnight on `date`.
        var start: Minutes
        /// Imported from a calendar: "apple:<event id>" or "google:<event id>".
        /// "edited:" in front once she changed it here, so imports leave it be.
        /// nil for exams she added.
        var source: String? = nil
    }
    /// A wake window she chose for one particular morning (exam mode), kept
    /// until that morning has passed so later pushes don't overwrite it.
    struct AlarmOverride: Codable, Hashable {
        /// Midnight of the morning it's for.
        var wakeDay: Date
        /// Minutes after midnight of `wakeDay`.
        var start: Minutes
        var end: Minutes
        var window: TimeRange { TimeRange(start, end) }
    }

    var onboarded = false
    var name: String?
    var cycleSetup: CycleSetup = .natural
    /// She picked a cycle setup herself (onboarding must not pass with the
    /// `.natural` default untouched). Older saves: true once onboarded.
    var cycleSetupChosen = false
    /// A `BirthControl` raw value ("Combined pill", "Hormonal IUD"…).
    var birthControl: String?
    var conditions: [String] = []
    var showCalories = false
    var sickAlerts = true
    var drinksTracking = true
    var peakDipNudges = true
    /// For fitness age.
    var sex: FitnessAge.Sex = .female
    var ageYears: Int?

    /// Pill, ring or patch: the day she took pill 1 (or put in the ring /
    /// patch) of the current pack. Later packs follow on automatically.
    var packStartDate: Date?
    /// 21 for 21+7, 24 for 24+4, 28 for continuous use (no break).
    var packActiveDays = 21
    var packLength = 28
    /// A pack check she answered "not now" to: the new-pack start or bleed
    /// date it was about, so the same prompt doesn't come back.
    var packCheckDismissed: Date?

    /// Minutes added to the learned sleep need by the user (±15 steps).
    var sleepNeedAdjustment = 0
    /// Latest time she has to be up, minutes after midnight (default 8:30).
    var upBy: Minutes = 510
    /// Planned bedtime, minutes relative to the wake day (default 12:30am).
    var bedtime: Minutes = 30
    var smartAlarmEnabled = false
    /// The smart alarm skips Saturday and Sunday mornings.
    var alarmWeekdaysOnly = true
    /// A regular iPhone alarm at the smart alarm's latest time, in case the
    /// Watch can't wake her (iOS 26.1+).
    var phoneBackupAlarm = false
    var alarmOverride: AlarmOverride?
    var examModeOn = false
    var exams: [Exam] = []
    var weeklyGoal: String?
    /// Clock-change plan: a `TimeChangePlanner.Strategy` raw value.
    var timeChangeStrategy = TimeChangePlanner.Strategy.keepClockTimes.rawValue
    /// Bedtime reminders for the clock-change plan. Never touches alarms.
    var timeChangeReminders = false

    var checkIns: [CheckIn] = []
    var savedDrinks: [Drink] = Drink.common.prefix(1).map { $0 }
    var drinkLog: [LoggedDrink] = []
    /// 24 oz for new installs (Priya U1). Stored in ml like Apple Health.
    var bottleSizeML: Double = 24 * 29.5735
    /// 64 oz. Shown in ounces; stored in ml like Apple Health.
    var waterGoalML: Double = 64 * 29.5735
    var waterLog: [WaterEntry] = []
    var alcoholLog: [AlcoholEntry] = []
    var flowLog: [FlowEntry] = []
    var symptomLog: [SymptomEntry] = []
    var moodLog: [MoodEntry] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppData()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        onboarded = get(.onboarded, d.onboarded)
        name = get(.name, d.name)
        cycleSetup = get(.cycleSetup, d.cycleSetup)
        cycleSetupChosen = get(.cycleSetupChosen, onboarded)
        birthControl = get(.birthControl, d.birthControl)
        conditions = get(.conditions, d.conditions)
        showCalories = get(.showCalories, d.showCalories)
        sickAlerts = get(.sickAlerts, d.sickAlerts)
        drinksTracking = get(.drinksTracking, d.drinksTracking)
        // `friendStreaks` from older saves is ignored.
        peakDipNudges = get(.peakDipNudges, d.peakDipNudges)
        sex = get(.sex, d.sex)
        ageYears = get(.ageYears, d.ageYears)
        packStartDate = get(.packStartDate, d.packStartDate)
        packActiveDays = min(max(get(.packActiveDays, d.packActiveDays), 1), 28)
        packLength = min(max(get(.packLength, d.packLength), packActiveDays), 35)
        packCheckDismissed = get(.packCheckDismissed, d.packCheckDismissed)
        sleepNeedAdjustment = get(.sleepNeedAdjustment, d.sleepNeedAdjustment)
        upBy = get(.upBy, d.upBy)
        bedtime = get(.bedtime, d.bedtime)
        smartAlarmEnabled = get(.smartAlarmEnabled, d.smartAlarmEnabled)
        alarmWeekdaysOnly = get(.alarmWeekdaysOnly, d.alarmWeekdaysOnly)
        phoneBackupAlarm = get(.phoneBackupAlarm, d.phoneBackupAlarm)
        alarmOverride = get(.alarmOverride, d.alarmOverride)
        examModeOn = get(.examModeOn, d.examModeOn)
        exams = get(.exams, d.exams)
        weeklyGoal = get(.weeklyGoal, d.weeklyGoal)
        timeChangeStrategy = get(.timeChangeStrategy, d.timeChangeStrategy)
        timeChangeReminders = get(.timeChangeReminders, d.timeChangeReminders)
        checkIns = get(.checkIns, d.checkIns)
        savedDrinks = get(.savedDrinks, d.savedDrinks)
        drinkLog = get(.drinkLog, d.drinkLog)
        // A save without a bottle size predates the setting: it was 500 ml
        // then, so keep that rather than switching her to the new default.
        bottleSizeML = get(.bottleSizeML, 500)
        waterGoalML = get(.waterGoalML, d.waterGoalML)
        // 1,500 ml was the old metric default; move it to the new 64 oz one.
        if waterGoalML == 1500 { waterGoalML = d.waterGoalML }
        waterLog = get(.waterLog, d.waterLog)
        alcoholLog = get(.alcoholLog, d.alcoholLog)
        flowLog = get(.flowLog, d.flowLog)
        symptomLog = get(.symptomLog, d.symptomLog)
        moodLog = get(.moodLog, d.moodLog)
    }

    /// Entries from today's app day only (since the rollover, 4:00am or
    /// later after a late bedtime; until then the evening before still
    /// counts as today).
    static func today<T>(_ xs: [T], date: (T) -> Date) -> [T] { xs.filter { AppDay.contains(date($0)) } }
}

/// The app's day runs from one rollover to the next, so a late night still
/// belongs to the evening before: caffeine at 12:15am counts toward today's
/// bedtime, and water and mood don't reset at midnight. The rollover is the
/// later of 4:00am and two hours after her planned bedtime (a 3:00am
/// bedtime rolls over at 5:00am), never after noon.
enum AppDay {
    /// Minutes after midnight the app day rolls over. Set from her bedtime
    /// by `AppModel` (`rollover(forBedtime:)`); 4:00am by default.
    static var rolloverMinutes = 240
    /// The rollover's hour (4 for 4:00–4:59am). Prefer `isBeforeRollover`.
    static var rolloverHour: Int { rolloverMinutes / 60 }

    /// The later of 4:00am and planned bedtime + 2h, at most noon. `bedtime`
    /// is minutes relative to the wake day (12:30am = 30, 11pm = −60).
    static func rollover(forBedtime bedtime: Minutes) -> Minutes {
        min(max(240, bedtime + 120), 720)
    }

    /// Between midnight and the rollover: still the evening before.
    static func isBeforeRollover(_ date: Date = .now, calendar: Calendar = .current) -> Bool {
        Clock.minutesOfDay(date, calendar: calendar) < rolloverMinutes
    }

    /// Midnight of the app day that `date` belongs to (yesterday's date
    /// between midnight and the rollover).
    static func day(containing date: Date = .now, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: date)
        guard isBeforeRollover(date, calendar: calendar) else { return midnight }
        return calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
    }

    /// The rollover time on the app day that `date` belongs to.
    static func start(containing date: Date = .now, calendar: Calendar = .current) -> Date {
        let day = day(containing: date, calendar: calendar)
        return calendar.date(bySettingHour: rolloverMinutes / 60, minute: rolloverMinutes % 60, second: 0, of: day) ?? day
    }

    static func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day(containing: date, calendar: calendar), inSameDayAs: day(containing: now, calendar: calendar))
    }

    /// Wall-clock minutes of `date` relative to midnight of `appDay`
    /// (12:30am the next night is 1470). DST-safe: counts calendar days, not
    /// elapsed seconds.
    static func minutes(_ date: Date, relativeTo appDay: Date, calendar: Calendar = .current) -> Minutes {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: appDay), to: calendar.startOfDay(for: date)).day ?? 0
        return days * 1440 + Clock.minutesOfDay(date, calendar: calendar)
    }

    /// The date at wall-clock `minutes` relative to midnight of `appDay`
    /// (values of 1440+ land on the next calendar day).
    static func date(_ minutes: Minutes, relativeTo appDay: Date, calendar: Calendar = .current) -> Date {
        Clock.date(minutes, relativeTo: appDay, calendar: calendar)
    }

    /// Puts the wall-clock time of `time` into the app day of `appDay`:
    /// 11:45pm stays on that evening, 12:10am moves to the night after.
    static func place(_ time: Date, inAppDayOf appDay: Date, calendar: Calendar = .current) -> Date {
        let c = calendar.dateComponents([.hour, .minute, .second], from: time)
        let h = c.hour ?? 0, m = c.minute ?? 0
        let base = day(containing: appDay, calendar: calendar)
        let target = h * 60 + m < rolloverMinutes ? (calendar.date(byAdding: .day, value: 1, to: base) ?? base) : base
        return calendar.date(bySettingHour: h, minute: m, second: c.second ?? 0, of: target) ?? time
    }

    /// A clock time picked for a new log entry: the most recent time that
    /// clock time came round, within the last 24 hours. Only the picked
    /// hour and minute count (never the picker's own date), so 11:45pm
    /// picked at 12:30am is last night, and 9:00pm picked at 2:00pm is
    /// yesterday evening. A time within the last minute (or "now") stays as
    /// it is.
    static func pastTime(_ picked: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        if abs(picked.timeIntervalSince(now)) <= 60 { return min(picked, now) }
        let c = calendar.dateComponents([.hour, .minute], from: picked)
        let today = calendar.startOfDay(for: now)
        let candidate = calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: today,
                                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? picked
        if candidate <= now { return candidate }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return now }
        let earlier = calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: yesterday,
                                    matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? now
        return min(earlier, now)
    }

    /// The one rule for a bedtime picked as a clock time (minutes after
    /// midnight): noon or later is the evening before the wake day (11:00pm
    /// is −60), before noon is after midnight (12:30am is 30). Check
    /// `AppDay.timeInBed` against up-by to warn about a bedtime after it.
    static func bedtime(fromClock clock: Minutes) -> Minutes {
        let c = ((clock % 1440) + 1440) % 1440
        return c >= 720 ? c - 1440 : c
    }

    /// Minutes from bedtime (wake-day minutes) to up-by. Zero or less means
    /// the bedtime is after the wake time: show a warning, not a plan.
    static func timeInBed(bedtime: Minutes, upBy: Minutes) -> Minutes { upBy - bedtime }

    /// An edited entry: a time-only change stays in the entry's own app day;
    /// a change of date is kept. Never in the future.
    static func editedTime(_ new: Date, original: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let sameCalendarDay = calendar.isDate(new, inSameDayAs: original)
        let placed = sameCalendarDay ? place(new, inAppDayOf: original, calendar: calendar) : new
        return min(placed, now)
    }
}

extension AppData.LoggedDrink {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        drinkID = try c.decode(UUID.self, forKey: .drinkID)
        name = try c.decode(String.self, forKey: .name)
        mg = try c.decode(Int.self, forKey: .mg)
        date = try c.decode(Date.self, forKey: .date)
    }
}

@MainActor
final class DataStore: ObservableObject {
    @Published var data: AppData {
        didSet {
            save()
            onChange?(oldValue, data)
        }
    }
    /// Called after every change with the old and new data (AppModel uses it
    /// to keep the Watch and notifications in step with settings).
    var onChange: ((AppData, AppData) -> Void)?
    private let url: URL

    init(filename: String = "app-data.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(filename)
        if DemoMode.resetData {
            try? FileManager.default.removeItem(at: url)
            UserDefaults.standard.removeObject(forKey: AppModel.sampleDataKey)
        }
        if let raw = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            data = decoded
        } else {
            data = AppData()
        }
    }

    private func save() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: url, options: .atomic)
    }

    /// The check-in done in the same app day as `date` (pass `.now` for
    /// "done today?"). A check-in at 1am belongs to the evening before.
    func checkIn(on date: Date) -> AppData.CheckIn? {
        let day = AppDay.day(containing: date)
        return data.checkIns.last { Calendar.current.isDate(AppDay.day(containing: $0.date), inSameDayAs: day) }
    }

    /// The morning check-in for the night that ended on `wakeDay` (a
    /// calendar day): one done during that app day.
    func checkIn(forWakeDay wakeDay: Date) -> AppData.CheckIn? {
        let cal = Calendar.current
        return data.checkIns.last { cal.isDate(AppDay.day(containing: $0.date), inSameDayAs: wakeDay) }
    }

    var birthControl: BirthControl? {
        data.cycleSetup == .hormonal ? data.birthControl.flatMap(BirthControl.init(rawValue:)) : nil
    }
}
