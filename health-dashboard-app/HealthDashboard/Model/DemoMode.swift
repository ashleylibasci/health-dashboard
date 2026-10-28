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
    static let exams = args.contains("-demoExams")
    #else
    static let isOn = false, sick = false, resetData = false, exams = false
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
}
