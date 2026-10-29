import Foundation
import HealthCore

/// The late-night cushion (H-C3): two or three nights before a known short
/// night, a nudge to go to bed a little earlier. Never "bank", never a
/// number of hours; tonight's bedtime itself doesn't change.
extension AppModel {
    /// How much earlier the nudge suggests.
    static let cushionMinutes = 20

    /// The exam a short night is coming before: one of hers (not an
    /// example) two or three nights away, that either starts early enough
    /// to get her up at least 30 minutes before her usual up-by, or falls
    /// while exam-week mode is on (late study nights). Nil otherwise.
    var cushionExam: UpcomingExam? {
        upcomingExams.first { exam in
            guard (2...3).contains(exam.daysUntil) else { return false }
            // Up 70 minutes before the start, as the exam plan has it.
            let examWake = exam.start - 70
            return store.data.examModeOn || examWake <= store.data.upBy - 30
        }
    }
}
