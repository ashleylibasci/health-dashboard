import Foundation

/// Optional chips in the morning check-in (D-P3): college life no watch can
/// measure. Saved with the check-in's tags under `rawValue` and paired, as
/// every check-in is, with the night that ended that morning, so Patterns
/// can compare those nights with the rest.
enum DayTag: String, CaseIterable, Identifiable {
    case exam = "Exam"
    case lateStudy = "Late study"
    case workout = "Workout"
    case party = "Party"
    case sick = "Sick"

    var id: String { rawValue }

    /// On the chip: what the morning's check-in means by it.
    var label: String {
        switch self {
        case .exam: return "Exam today"
        case .lateStudy: return "Studied late"
        case .workout: return "Worked out yesterday"
        case .party: return "Party last night"
        case .sick: return "Feeling sick"
        }
    }
}
