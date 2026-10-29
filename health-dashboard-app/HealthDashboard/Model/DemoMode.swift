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
/// - `-demoPillHistory` (with `-demoCycle pill`): four earlier packs of
///   pills (three missed), withdrawal bleeds, spotting, symptoms and
///   check-ins, for the pill-history screens and the visit summary.
/// - `-demoPillEvent vomiting|spotting` (with `-demoCycle pill`): that
///   logged today, for the pill callouts.
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
    /// `-demoOpen cycle|cycleSettings`: opens on that screen (Body tab), for
    /// screenshots.
    static let open = value(after: "-demoOpen")
    static let exams = args.contains("-demoExams")
    static let fuel = args.contains("-demoFuel")
    static let pillHistory = args.contains("-demoPillHistory")
    static let pillEvent = value(after: "-demoPillEvent")
    #else
    static let isOn = false, sick = false, resetData = false, pillNotice = false, away = false, exams = false, fuel = false
    static let pillHistory = false
    static let pillEvent: String? = nil
    static let open: String? = nil
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
            data.packStartDate = cal.date(byAdding: .day, value: -17, to: today)
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
            data.pillsTaken = (1...17).filter { $0 != 11 }.compactMap { day in
                cal.date(byAdding: .minute, value: 21 * 60 - 7 + day % 5, to: cal.date(byAdding: .day, value: day - 18, to: today) ?? today)
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
            let wobble = i % 3 == 0 ? 1 : 0
            return [AppData.MoodRating(date: date, scale: .mood, value: inBreak ? 2 + (i % 2) : 3 + (i % 4 == 0 ? 0 : 1)),
                    AppData.MoodRating(date: date, scale: .anxiety, value: inBreak ? 3 : 2 + (i % 5 == 0 ? 1 : 0)),
                    AppData.MoodRating(date: date, scale: .irritability, value: inBreak ? 3 + wobble : 1 + wobble)]
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
