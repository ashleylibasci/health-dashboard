import Foundation

/// How fresh her VO₂ max estimate is (H-E5). The Watch only makes one on
/// outdoor walks, runs and hikes, so a stale estimate makes fitness age
/// stale too.
extension AppModel {
    /// An estimate older than this gets the "brisk outdoor walk" tip.
    static let vo2StaleDays = 30

    /// Days since the latest VO₂ max estimate. Nil without one.
    var vo2MaxAgeDays: Int? {
        guard let latest = vo2MaxHistory.map(\.date).max() else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: latest), to: cal.startOfDay(for: .now)).day
    }

    var vo2MaxIsStale: Bool { (vo2MaxAgeDays ?? 0) >= Self.vo2StaleDays }

    /// "today", "3 days ago", "6 weeks ago", "4 months ago".
    var vo2MaxAgeText: String? {
        guard let d = vo2MaxAgeDays else { return nil }
        switch d {
        case ..<1: return "today"
        case 1: return "yesterday"
        case ..<14: return "\(d) days ago"
        case ..<60: return "\(d / 7) weeks ago"
        default: return "\(d / 30) months ago"
        }
    }
}
