import Foundation
import HealthCore

/// The exam crunch radar (H-B3): her heaviest exam week, named two weeks
/// ahead, with exam-week mode turned on early for the whole stretch.
extension AppModel {
    struct ExamCrunch: Hashable {
        var first: Date
        var last: Date
        var count: Int

        /// "Nov 9–13", or "Nov 30–Dec 4" across months.
        var label: String {
            let cal = Calendar.current
            let start = first.formatted(.dateTime.month(.abbreviated).day())
            if cal.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(start)\u{2013}\(last.formatted(.dateTime.day()))"
            }
            return "\(start)\u{2013}\(last.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    /// A week counts as a crunch with this many exams in it.
    static let crunchExams = 3
    /// Named this many days before its first exam.
    static let crunchLookahead = 14
    /// Exam-week mode turns on this many days before its first exam.
    static let crunchModeLead = 3

    /// Her calendar week with the most exams (3 or more), if its first exam
    /// is within two weeks. Her own exams only, never the examples.
    var examCrunch: ExamCrunch? {
        let cal = Calendar.current
        let weeks = Dictionary(grouping: upcomingExams) { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        // Most exams first; between equal weeks, the sooner one.
        let busiest = weeks
            .filter { $0.value.count >= Self.crunchExams }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .first?.value
        guard let exams = busiest?.sorted(by: { $0.date < $1.date }), let first = exams.first, let last = exams.last,
              first.daysUntil <= Self.crunchLookahead else { return nil }
        return ExamCrunch(first: first.date, last: last.date, count: exams.count)
    }

    /// Turns exam-week mode on 3 days before a crunch week, once per crunch
    /// (if she turns it off again, it stays off). Runs on every refresh.
    func applyExamCrunch() {
        guard let crunch = examCrunch, !store.data.examModeOn,
              store.data.sleepExtras.crunchTurnedOn != crunch.first else { return }
        let days = Calendar.current.dateComponents([.day], from: appDayDate, to: crunch.first).day ?? .max
        guard days <= Self.crunchModeLead else { return }
        store.data.examModeOn = true
        store.data.sleepExtras.crunchTurnedOn = crunch.first
    }
}
