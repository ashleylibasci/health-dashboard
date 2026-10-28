import Foundation
import HealthCore

/// Small derived values for the Today, Sleep, Energy and planning screens.
/// Computed only; nothing here is stored.
extension AppModel {

    // MARK: The real clock vs. the app day

    /// Between midnight and the rollover: the app day is still "tonight", but
    /// on the calendar the next wake-up is later today.
    var isAfterMidnight: Bool { AppDay.isBeforeRollover() }

    /// The greeting by the real clock (never "Good morning" at 1am).
    var greetingPart: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<24: return "Good evening"
        default: return "Still up"
        }
    }

    /// "Tomorrow" before midnight; "This morning" after midnight, when the
    /// next wake-up is later today.
    var nextWakeDayLabel: String { isAfterMidnight ? "This morning" : "Tomorrow" }
    /// "Wednesday": the weekday of the next wake-up.
    var nextWakeDayName: String { nextWakeDay.formatted(.dateTime.weekday(.wide)) }

    // MARK: Conditions

    /// With an eating-disorder history, the app shows no step goals, effort
    /// targets or exercise prescriptions, no calories and no water goal.
    var hidesEffortTargets: Bool { store.data.conditions.contains("Eating-disorder history") }

    // MARK: Usual values

    /// "your usual 78" when it's her own average, otherwise "the starting
    /// point of 78": a fixed value the app begins from, not a measured norm
    /// (Sam N14), until 7 days give her own.
    var recoveryUsualPhrase: String {
        recoveryUsualIsPersonal ? "your usual \(recoveryUsual)" : "the starting point of \(recoveryUsual)"
    }
    var energyUsualPhrase: String {
        energyUsualIsPersonal ? "your usual \(energyUsual)" : "the starting point of \(energyUsual)"
    }
    /// For a short note: "Your usual is 78." or "Starting point 78 until
    /// your own usual (7 days)."
    var recoveryUsualNote: String {
        recoveryUsualIsPersonal ? "Your usual is \(recoveryUsual)."
            : "Compared with a starting point of \(recoveryUsual) until your Watch learns your usual (7 days)."
    }

    // MARK: Exams

    /// Exams she added that haven't happened yet (today's included), soonest
    /// first. "Today" is the app day: at 1am a 9am exam is tomorrow morning,
    /// after tonight's sleep, and yesterday's exam is still today.
    var upcomingExams: [UpcomingExam] {
        let cal = Calendar.current
        let today = appDayDate
        return store.data.exams
            .filter { cal.startOfDay(for: $0.date) >= today }
            .map { UpcomingExam(exam: $0, today: today, calendar: cal) }
            .sorted { ($0.daysUntil, $0.start) < ($1.daysUntil, $1.start) }
    }

    /// What the exam screens show: her own exams, or, while the app is still
    /// on example data and she hasn't added any, two example exams.
    var examsToShow: [UpcomingExam] {
        let mine = upcomingExams
        if mine.isEmpty && usingSampleData && store.data.exams.isEmpty { return UpcomingExam.samples() }
        return mine
    }

    /// True when `examsToShow` are the examples.
    var examsAreExamples: Bool { examsToShow.first?.isExample ?? false }

    // MARK: Week recap

    /// Days in last week's recap that are her own recorded nights (0 while
    /// the recap shows the example week).
    var weekRecapDays: Int {
        let cal = Calendar.current
        return lastWeek.filter { realNightDays.contains(cal.startOfDay(for: $0.date)) }.count
    }
}

extension AppModel {
    /// The zone one-liner, without workout suggestions when she has an
    /// eating-disorder history.
    func zoneOneLinerShown(_ kind: EnergyDay.Zone.Kind) -> String {
        if kind == .secondWind && hidesEffortTargets { return "your energy lifts again. Good for group study or seeing friends." }
        return Self.zoneOneLiner(kind)
    }

    /// The zone action, without workout suggestions when she has an
    /// eating-disorder history.
    func zoneActionShown(_ kind: EnergyDay.Zone.Kind) -> String {
        if kind == .secondWind && hidesEffortTargets { return "Good for group study or seeing friends. Wrap up anything intense a couple of hours before bed." }
        return Self.zoneAction(kind)
    }
}

extension AppModel {
    /// Today's recovery as the screens show it. Without a recorded night it
    /// leaves sleep out (an old night would be misleading); with neither
    /// sleep nor heart readings there is no number.
    var recoveryShown: Int? {
        if lastNightIsFresh { return recovery }
        guard hasHeartData else { return nil }
        return Recovery.score(usual: Double(Self.recoveryAnchor), hrvDeltaPct: hrvDeltaPct,
                              restingHRDelta: restingHRDelta, sleepShortfall: 0, cycle: cycleHeartShift)
    }
}
