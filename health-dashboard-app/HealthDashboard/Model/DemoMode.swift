import Foundation
import HealthCore

/// Launch arguments for the simulator and UI tests (Debug builds only; a
/// Release build ignores them). Demo mode shows the example data, labelled as
/// usual by `SampleDataBanner`, and never asks Apple Health or writes to it.
///
/// - `-demo`: example data.
/// - `-demoSick`: example data with several overnight signals up, so the sick
///   check fires.
/// - `-demoCycle <setup>`: skips setup with that cycle and some logged
///   bleeds. `pill` (combined, pill 18 of 21+7), `hormonalIUD` (periods
///   mostly stopped), `natural`, `copper` (copper IUD, heavier periods) or
///   `irregular` (35–60 day cycles). `-demoPill` is short for `-demoCycle pill`.
/// - `-demoConditions "PCOS,PMDD"`: health conditions, by their names in
///   Settings.
/// - `-resetData`: starts from a fresh install (setup, no logs).
/// - `-demoExams`: with `-demoCycle`, a set of exams: an early quiz in two
///   days, a four-exam week about two weeks out, and ten past exams (nine
///   with an after-exam check-in).
/// - `-demoFuel` (with `-demoCycle`): caffeine, alcohol and water logs, a
///   big night last night and a hard training day today.
/// - `-demoClock 14:30`: Today as if it were that time (see `clock`).
/// - `-demoPillHistory` (with `-demoCycle pill`): four earlier packs of
///   pills (three missed), withdrawal bleeds, spotting, symptoms and
///   check-ins, for the pill-history screens and the visit summary.
/// - `-demoPillEvent vomiting|spotting` (with `-demoCycle pill`): that
///   logged today, for the pill callouts.
/// - `-demoBedtimeActivity on|openWatch|off|hidden`: the bedtime Live
///   Activity right away, with that Watch alarm state.
/// - `-demoPatterns` (with `-demoCycle`): two months of morning check-ins
///   with tags (late study, parties, workouts, a sick week) and three past
///   exam weeks, so Patterns has something to find (D-P2).
/// - `-demoWeekStory`: as if it were Sunday evening, so "Your week" on
///   Today is marked new (D-P1).
/// - `-demoTiles pill,energy,caffeine,water`: those At a glance tiles
///   pinned, in that order (D-P4).
///
/// Add them in Xcode under Product → Scheme → Edit Scheme → Run → Arguments.
enum DemoMode {
    #if DEBUG
    private static let args = ProcessInfo.processInfo.arguments
    private static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static let sick = args.contains("-demoSick")
    static let cycle = value(after: "-demoCycle") ?? (args.contains("-demoPill") ? "pill" : nil)
    static let conditions = value(after: "-demoConditions")?
        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    static let isOn = args.contains("-demo") || sick || cycle != nil
    static let resetData = args.contains("-resetData")
    /// `-demoPillNotice`: today's pill reminder 10 seconds after launch, to
    /// see the notification and its Taken button.
    static let pillNotice = args.contains("-demoPillNotice")
    /// `-demoAway`: with `-demoCycle pill`, her pill time belongs to a time
    /// zone 3 hours from the phone's, as if she'd travelled.
    static let away = args.contains("-demoAway")
    /// `-demoOpen cycle|cycleSettings|visitSummary|recovery`: opens on that screen
    /// (Body tab), for screenshots. The pill-visit summary also saves its
    /// PDF in Documents as visit-summary.pdf.
    static let open = value(after: "-demoOpen")
    static let exams = args.contains("-demoExams")
    static let fuel = args.contains("-demoFuel")
    /// `-demoClock 14:30`: Today greets, orders its cards and reads energy
    /// now as if it were that time (screenshots of the morning, afternoon
    /// and evening). Other screens keep the real clock. In app-day
    /// minutes, so `00:30` is 1470.
    static let clock: Minutes? = value(after: "-demoClock").flatMap { text in
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        let minutes = parts[0] * 60 + parts[1]
        return minutes < AppDay.rolloverMinutes ? minutes + 1440 : minutes
    }
    static let pillHistory = args.contains("-demoPillHistory")
    static let pillEvent = value(after: "-demoPillEvent")
    /// `-demoPackDay <n>`: with `-demoCycle pill`, today is pill n (18 by
    /// default), for break-day previews.
    static let packDay = min(max(Int(value(after: "-demoPackDay") ?? "") ?? 18, 2), 28)
    /// `-demoBedtimeActivity on|openWatch|off|hidden`: the bedtime Live
    /// Activity straight away, with that Watch alarm state.
    static let bedtimeActivity = value(after: "-demoBedtimeActivity")
    static let patterns = args.contains("-demoPatterns")
    static let weekStoryOut = args.contains("-demoWeekStory")
    static let tiles = value(after: "-demoTiles")
    #else
    static let patterns = false, weekStoryOut = false
    static let tiles: String? = nil
    static let isOn = false, sick = false, resetData = false, pillNotice = false, away = false, exams = false, fuel = false
    static let pillHistory = false
    static let pillEvent: String? = nil
    static let packDay = 18
    static let open: String? = nil
    static let clock: Minutes? = nil
    static let bedtimeActivity: String? = nil
    static let cycle: String? = nil
    static let conditions: [String] = []
    #endif

    /// `-demoCycle`: a finished setup with that cycle, on a fresh install.
    @MainActor
    static func applySetup(store: DataStore, model: AppModel) {
        guard let cycle, !store.data.onboarded else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func bleed(daysAgo: Int, days: Int, heavy: Bool = false) -> [AppData.FlowEntry] {
            (0..<days).compactMap { d in
                guard let date = cal.date(byAdding: .day, value: -daysAgo + d, to: today) else { return nil }
                let flow: AppData.Flow = d == 0 || d == days - 1 ? .light : (heavy && d < 3 ? .heavy : .medium)
                return AppData.FlowEntry(date: date, flow: flow)
            }
        }
        var data = store.data
        data.cycleSetupChosen = true
        data.conditions = conditions
        switch cycle {
        case "pill":
            data.cycleSetup = .hormonal
            data.birthControl = BirthControl.combinedPill.rawValue
            // Pill 18 of 21+7 today. Set in the same save as the method: a
            // method change on its own resets the pack (normalizePack).
            data.packActiveDays = 21
            data.packLength = 28
            data.packStartDate = cal.date(byAdding: .day, value: -(packDay - 1), to: today)
            // Pills 1–17 marked taken at about 9pm, except pill 11, and the
            // 9pm reminder on (H-A1).
            data.pillReminder = true
            // On her last pack (H-A6).
            data.refillPacks = 1
            data.refillCountedFrom = data.packStartDate
            // -demoAway: her pill time is set back home, 3 hours from here (H-A11).
            if away {
                data.pillHomeTimeZone = TimeZone.current.identifier == "America/New_York" ? "America/Los_Angeles" : "America/New_York"
            }
            data.pillsTaken = (1...min(packDay - 1, 21)).filter { $0 != 11 }.compactMap { day in
                cal.date(byAdding: .minute, value: 21 * 60 - 7 + day % 5, to: cal.date(byAdding: .day, value: day - packDay, to: today) ?? today)
            }
        case "hormonalIUD":
            data.cycleSetup = .hormonal
            data.birthControl = BirthControl.hormonalIUD.rawValue
            data.flowLog = [AppData.FlowEntry(date: cal.date(byAdding: .day, value: -71, to: today) ?? today, flow: .spotting)]
        case "copper":
            data.cycleSetup = .hormonal
            data.birthControl = BirthControl.copperIUD.rawValue
            data.flowLog = bleed(daysAgo: 67, days: 6, heavy: true) + bleed(daysAgo: 38, days: 6, heavy: true)
                + bleed(daysAgo: 9, days: 6, heavy: true)
        case "irregular":
            data.cycleSetup = .irregular
            data.birthControl = nil
            data.flowLog = bleed(daysAgo: 157, days: 5) + bleed(daysAgo: 99, days: 5) + bleed(daysAgo: 52, days: 6)
        default:   // natural
            data.cycleSetup = .natural
            data.birthControl = nil
            data.flowLog = bleed(daysAgo: 70, days: 5) + bleed(daysAgo: 41, days: 5) + bleed(daysAgo: 12, days: 5)
        }
        if exams { addExams(to: &data, today: today, calendar: cal) }
        if fuel { seedFuelLogs(&data, today: today, calendar: cal) }
        if patterns { seedPatterns(&data, today: today, calendar: cal) }
        if let tiles { data.insights.glanceTiles = tiles.split(separator: ",").map(String.init) }
        if cycle == "pill", pillHistory { seedPillHistory(&data, today: today, calendar: cal) }
        if cycle == "pill", let pillEvent { seedPillEvent(pillEvent, &data, today: today, calendar: cal) }
        data.onboarded = true
        store.data = data
    }

    /// `-demoExams`: see the list at the top.
    private static func addExams(to data: inout AppData, today: Date, calendar cal: Calendar) {
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today) ?? today }
        func exam(_ title: String, _ kind: String, _ offset: Int, _ start: Minutes) -> AppData.Exam {
            AppData.Exam(title: title, kind: kind, date: day(offset), start: start)
        }
        // The Monday 10 to 16 days out, and three more exams that week.
        let weekday = cal.component(.weekday, from: today)        // 1 = Sunday, 2 = Monday
        let nextMonday = (9 - weekday) % 7 + 7
        let monday = nextMonday < 10 ? nextMonday + 7 : nextMonday
        data.exams = [exam("BIOL 210", "Quiz", 2, 480),
                      exam("ECON 201", "Midterm", monday, 600), exam("STAT 400", "Midterm", monday + 1, 540),
                      exam("PSYC 101", "Exam", monday + 3, 780), exam("CHEM 101", "Final", monday + 4, 480),
                      exam("ENGL 102", "Essay exam", -2, 600)]
        let past: [(String, Int, SleepExtrasData.ExamReflection.Felt)] = [
            ("STAT 400 quiz", -6, .well), ("ECON 201 quiz", -9, .okay), ("BIOL 210 lab", -13, .rough),
            ("CHEM 101 quiz", -16, .well), ("PSYC 101 quiz", -20, .okay), ("STAT 400 quiz", -27, .well),
            ("ECON 201 quiz", -30, .rough), ("BIOL 210 quiz", -34, .well), ("CHEM 101 midterm", -41, .okay)]
        data.sleepExtras.examReflections = past.map {
            SleepExtrasData.ExamReflection(id: UUID(), title: $0.0, examDay: day($0.1), felt: $0.2)
        }
    }

    /// `-demoFuel` (with `-demoCycle`): logs for the caffeine, alcohol and
    /// water screens. A big night last night (a red cup of wine and two
    /// shots), four weeks of morning lattes with a late coffee every third
    /// day, a bottle of water this morning, and tiredness on heavy days.
    @MainActor
    private static func seedFuelLogs(_ data: inout AppData, today: Date, calendar cal: Calendar) {
        func at(_ daysAgo: Int, _ minutes: Int) -> Date {
            cal.date(byAdding: .minute, value: minutes, to: cal.date(byAdding: .day, value: -daysAgo, to: today) ?? today) ?? today
        }
        let latte = Drink.common[0], drip = AppModel.referenceCoffee
        data.alcoholLog = [AppData.AlcoholEntry(date: at(1, 22 * 60), kind: "Wine", count: 1, pour: "Wine.redCup"),
                           AppData.AlcoholEntry(date: at(1, 23 * 60 + 30), kind: "Shot", count: 2, pour: "Shot.standard")]
        data.drinkLog = (1...28).flatMap { d -> [AppData.LoggedDrink] in
            var drinks = [AppData.LoggedDrink(drinkID: latte.id, name: latte.name, mg: latte.caffeineMg, date: at(d, 9 * 60 + 30))]
            if d % 3 == 0 {
                drinks.append(AppData.LoggedDrink(drinkID: drip.id, name: drip.name, mg: drip.caffeineMg, date: at(d, 16 * 60 + 30)))
            }
            return drinks
        }
        data.waterLog = [AppData.WaterEntry(date: at(0, 10 * 60), ml: data.bottleSizeML)]
        data.symptomLog = data.flowLog.filter { $0.flow == .heavy }.map { AppData.SymptomEntry(date: $0.date, symptoms: ["Fatigue"]) }
    }

    /// `-demoPatterns`: a check-in most mornings of the last 60 days, with
    /// late study every sixth, a party every seventh, a workout every third
    /// and five sick mornings a month ago; and three past exams (unless
    /// `-demoExams` set some).
    private static func seedPatterns(_ data: inout AppData, today: Date, calendar cal: Calendar) {
        data.checkIns = (1...60).compactMap { back -> AppData.CheckIn? in
            guard back % 7 != 5, let day = cal.date(byAdding: .day, value: -back, to: today),
                  let date = cal.date(byAdding: .minute, value: 8 * 60 + 20, to: day) else { return nil }
            var tags: [String] = []
            if back % 6 == 2 { tags.append(DayTag.lateStudy.rawValue) }
            if back % 7 == 6 { tags.append(DayTag.party.rawValue) }
            if back % 3 == 0 { tags.append(DayTag.workout.rawValue) }
            if (30...35).contains(back) { tags.append(DayTag.sick.rawValue) }
            return AppData.CheckIn(date: date, awake: 3 + back % 2, tags: tags)
        }
        if data.exams.isEmpty {
            data.exams = [(-9, "STAT 400"), (-23, "ECON 201"), (-44, "BIOL 210")].compactMap { offset, title in
                cal.date(byAdding: .day, value: offset, to: today).map { AppData.Exam(title: title, kind: "Midterm", date: $0, start: 600) }
            }
        }
    }

    /// `-demoPillHistory`: four packs before the current one (21 + 7, on
    /// this pill since the first). Pill 2 of the oldest-but-one pack, pill
    /// 9 of the last and pill 15 of the one before were missed. Bleeds in
    /// every break, getting lighter; spotting early on; headaches and
    /// cramps mostly in break weeks; morning check-ins and mood a little
    /// lower then.
    @MainActor
    private static func seedPillHistory(_ data: inout AppData, today: Date, calendar cal: Calendar) {
        guard let start = data.packStartDate else { return }
        let packs = -4 ... -1
        func day(_ pack: Int, _ d: Int, minutes: Int = 0) -> Date {
            let midnight = cal.date(byAdding: .day, value: pack * 28 + d - 1, to: start) ?? start
            return cal.date(byAdding: .minute, value: minutes, to: midnight) ?? midnight
        }
        data.methodChangedDate = day(-4, 1)
        let missed: Set<[Int]> = [[-3, 2], [-2, 15], [-1, 9]]
        data.pillsTaken = packs.flatMap { pack in
            (1...21).filter { !missed.contains([pack, $0]) }.map { day(pack, $0, minutes: 21 * 60 - 10 + ($0 * 7) % 25) }
        } + data.pillsTaken
        // Bleed days 23–27 in the oldest packs, 23–26 later; lighter over time.
        let bleeds: [Int: [AppData.Flow]] = [-4: [.light, .heavy, .medium, .medium, .light],
                                             -3: [.light, .medium, .medium, .light, .spotting],
                                             -2: [.light, .medium, .light, .spotting],
                                             -1: [.light, .medium, .light, .spotting]]
        var flows: [AppData.FlowEntry] = []
        for (pack, list) in bleeds {
            for (i, flow) in list.enumerated() { flows.append(.init(date: day(pack, 23 + i, minutes: 9 * 60), flow: flow)) }
        }
        // Breakthrough spotting in the first two packs.
        flows += [.init(date: day(-4, 9, minutes: 9 * 60), flow: .spotting), .init(date: day(-4, 10, minutes: 9 * 60), flow: .spotting),
                  .init(date: day(-3, 12, minutes: 9 * 60), flow: .spotting)]
        data.flowLog = (data.flowLog + flows).sorted { $0.date < $1.date }
        var symptoms: [AppData.SymptomEntry] = []
        for pack in packs {
            symptoms.append(.init(date: day(pack, 22, minutes: 20 * 60), symptoms: ["Headache"]))
            symptoms.append(.init(date: day(pack, 23, minutes: 20 * 60), symptoms: ["Cramps", "Headache"]))
            if pack != -2 { symptoms.append(.init(date: day(pack, 24, minutes: 20 * 60), symptoms: ["Headache", "Fatigue"])) }
        }
        symptoms.append(.init(date: day(-2, 6, minutes: 20 * 60), symptoms: ["Headache"]))
        data.symptomLog = (data.symptomLog + symptoms).sorted { $0.date < $1.date }
        // A morning check-in most days: 2–3 in break weeks, 3–4 otherwise.
        let firstDay = day(-4, 1)
        let days = cal.dateComponents([.day], from: firstDay, to: today).day ?? 0
        data.checkIns = (0..<days).compactMap { i -> AppData.CheckIn? in
            guard i % 5 != 3, let date = cal.date(byAdding: .minute, value: i * 1440 + 8 * 60 + 15, to: firstDay) else { return nil }
            let packDay = i % 28 + 1
            let awake = packDay > 21 ? 2 + (i % 3 == 0 ? 1 : 0) : 3 + (i % 2)
            return AppData.CheckIn(date: date, awake: awake, tags: [])
        }
        // Mood, anxiety and irritability most evenings (B1): lower mood and
        // more irritable in break weeks.
        data.moodRatings = (0..<days).flatMap { i -> [AppData.MoodRating] in
            guard i % 6 != 4, let date = cal.date(byAdding: .minute, value: i * 1440 + 21 * 60 + 20, to: firstDay) else { return [] }
            let inBreak = i % 28 >= 21
            // A day-to-day wobble that doesn't repeat pack to pack.
            func wobble(_ salt: Int) -> Int { (i * i * 7 + i * 13 + salt) % 9 }
            let mood = inBreak ? (wobble(1) < 5 ? 2 : 3) : (wobble(1) < 2 ? 3 : wobble(1) == 8 ? 5 : 4)
            let anxiety = inBreak ? (wobble(2) < 6 ? 3 : 2) : (wobble(2) < 6 ? 2 : wobble(2) == 8 ? 4 : 3)
            let irritable = inBreak ? (wobble(3) < 4 ? 4 : 3) : (wobble(3) < 6 ? 1 : 2)
            return [AppData.MoodRating(date: date, scale: .mood, value: mood),
                    AppData.MoodRating(date: date, scale: .anxiety, value: anxiety),
                    AppData.MoodRating(date: date, scale: .irritability, value: irritable)]
        }
    }

    /// `-demoPillHistory`: the example nights reach back four packs, with
    /// resting heart rate about 2 beats higher on break days (E2). The
    /// demo pack started `packDay` − 1 days ago.
    static func pillHistoryNights(_ nights: [NightRecord], today: Date = .now, calendar cal: Calendar = .current) -> [NightRecord] {
        let day0 = cal.startOfDay(for: today)
        let older = nights.prefix(49).compactMap { n -> NightRecord? in
            guard let day = cal.date(byAdding: .day, value: -49, to: n.wakeDay) else { return nil }
            var copy = n
            copy.wakeDay = day
            return copy
        }
        guard let packStart = cal.date(byAdding: .day, value: -(packDay - 1), to: day0) else { return nights }
        let packs = PackCalendar(start: packStart, activeDays: 21, packLength: 28)
        return (older + nights).map { n in
            guard packs.isBreak(day: packs.position(of: n.wakeDay, calendar: cal).day) else { return n }
            var copy = n
            copy.outcome.restingHRDelta = (n.outcome.restingHRDelta ?? 0) + 2
            return copy
        }
    }

    /// `-demoPillEvent`: vomiting this morning, or spotting yesterday and
    /// today.
    @MainActor
    private static func seedPillEvent(_ event: String, _ data: inout AppData, today: Date, calendar cal: Calendar) {
        let morning = cal.date(byAdding: .minute, value: 7 * 60, to: today) ?? today
        switch event {
        case "vomiting":
            data.symptomLog.append(.init(date: morning, symptoms: ["Vomiting"]))
        case "spotting":
            let yesterday = cal.date(byAdding: .day, value: -1, to: morning) ?? morning
            data.flowLog += [.init(date: yesterday, flow: .spotting), .init(date: morning, flow: .spotting)]
        default:
            break
        }
    }
}
