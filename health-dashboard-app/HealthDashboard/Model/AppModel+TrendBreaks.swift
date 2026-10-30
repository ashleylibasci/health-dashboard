import Foundation
import HealthCore

/// Her break weeks behind the HRV, resting heart rate and sleep trends
/// (D-G3), from the same packs the pill-history features read (H-A10,
/// H-E2). A night counts by the day she woke, as in the pack-day baselines.
extension AppModel {
    /// The break days inside `domain`, as spans from the first break day's
    /// midnight to the midnight after the last, up to today. Combined pill
    /// with a pack set and a break, since her last method change; empty
    /// otherwise, so nothing is shaded.
    func breakSpans(in domain: ClosedRange<Date>) -> [ClosedRange<Date>] {
        guard let packs = packCalendar, packs.hasBreak else { return [] }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        let since = pillHistorySince.map { cal.startOfDay(for: $0) } ?? domain.lowerBound
        let from = max(domain.lowerBound, since)
        let to = min(domain.upperBound, tomorrow)
        guard from < to else { return [] }
        return (packs.position(of: from).pack...packs.position(of: to).pack).compactMap { pack in
            let last = packs.date(pack: pack, day: packs.packLength)
            let start = max(packs.date(pack: pack, day: packs.activeDays + 1), from)
            let end = min(cal.date(byAdding: .day, value: 1, to: last) ?? last, to)
            return start < end ? start...end : nil
        }
    }

    /// Whether `day` (a wake day) falls in a shaded break.
    func isBreakDay(_ day: Date) -> Bool {
        guard let position = packPosition(of: day), let packs = packCalendar else { return false }
        return packs.isBreak(day: position.day)
    }
}
