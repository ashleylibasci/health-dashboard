import Foundation

struct WeekLook: Equatable {
    var nights: Int
    var asleepMinutes: Double
    var bedtime: Double
    var restingHr: Double?
    var hrv: Double?
}

struct ExamWeekLens: Equatable {
    var exams: Int
    var examWeeks: WeekLook
    var normalWeeks: WeekLook
    var days: Int
}

/// Sleep, resting HR and HRV in the 6 nights before each exam, compared with her other nights.
/// The night after an exam is left out of "normal", since that's often catch-up sleep.
func examWeekLens(_ nights: [Night], restingHr: [String: Double], hrv: [String: Double], examDates: [String], days: Int = 365) -> ExamWeekLens? {
    guard let latest = nights.last?.date else { return nil }
    let recent = nights.filter { Day.between($0.date, latest) < days }
    let exams = Set(examDates).filter {
        let since = Day.between(latest, $0)
        return since <= 1 && since > -days
    }

    var runUp = Set<String>()
    for e in exams { for k in 1...6 { runUp.insert(Day.shift(e, -k)) } }
    let exam = recent.filter { runUp.contains($0.date) }
    let normal = recent.filter { !runUp.contains($0.date) && !exams.contains($0.date) }
    guard exam.count >= 5, normal.count >= 5 else { return nil }

    func look(_ ns: [Night]) -> WeekLook {
        func series(_ m: [String: Double]) -> Double? { mean(ns.compactMap { m[$0.wakeDate] }).map(round1) }
        return WeekLook(
            nights: ns.count,
            asleepMinutes: median(ns.map { Double($0.asleepMinutes) })!,
            bedtime: median(ns.map { Double($0.bedtime) })!,
            restingHr: series(restingHr),
            hrv: series(hrv)
        )
    }
    return ExamWeekLens(exams: exams.count, examWeeks: look(exam), normalWeeks: look(normal), days: days)
}
