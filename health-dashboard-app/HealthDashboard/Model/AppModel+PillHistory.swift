import Foundation
import HealthCore

/// Her past packs on the combined pill: the shared view the pill-history
/// features read (bleeds by pack, mood by pack day, break-week patterns,
/// pack-day baselines, the visit summary).
extension AppModel {
    /// The current pack, extended back in whole packs. Combined pill with a
    /// known pack day only.
    var packCalendar: PackCalendar? { pillPack.map(PackCalendar.init) }

    /// History counts from her last method change (nil: everything she
    /// logged).
    var pillHistorySince: Date? { store.data.methodChangedDate }

    /// Packs that have ended since her last method change, oldest first.
    var finishedPacks: [Int] {
        packCalendar?.finishedPacks(since: pillHistorySince, now: .now) ?? []
    }

    /// The pack day of a past date, if it's after her method change.
    func packPosition(of date: Date) -> PackCalendar.Position? {
        guard let cal = packCalendar else { return nil }
        if let since = pillHistorySince, date < Calendar.current.startOfDay(for: since) { return nil }
        return cal.position(of: date)
    }

    /// "Oct 4–31" for a pack.
    func packDateRange(_ pack: Int) -> String {
        guard let cal = packCalendar else { return "" }
        let start = cal.start(ofPack: pack), end = cal.date(pack: pack, day: cal.packLength)
        let style: Date.FormatStyle = .dateTime.month(.abbreviated).day()
        let sameMonth = Calendar.current.isDate(start, equalTo: end, toGranularity: .month)
        return "\(start.formatted(style))\u{2013}\(sameMonth ? end.formatted(.dateTime.day()) : end.formatted(style))"
    }

    // MARK: Bleeds by pack (H-A10)

    /// Her logged flow as `PackBleeds` levels (no-flow days left out).
    var packFlows: [(date: Date, level: PackBleeds.Level)] {
        store.data.flowLog.compactMap { entry -> (date: Date, level: PackBleeds.Level)? in
            let level: PackBleeds.Level? = switch entry.flow {
            case .none: nil
            case .spotting: .spotting
            case .light: .light
            case .medium: .medium
            case .heavy: .heavy
            }
            return level.map { (entry.date, $0) }
        }
    }

    /// The last six finished packs' bleeds, newest first. Empty until she's
    /// logged any flow in one.
    var packBleeds: [PackBleeds.Pack] {
        guard let cal = packCalendar else { return [] }
        let all = PackBleeds.summarize(packFlows, packs: finishedPacks.suffix(6), in: cal)
        guard all.contains(where: { $0.bleedDays > 0 || $0.activeDays > 0 }) else { return [] }
        return all.reversed()
    }

    static func flowWord(_ level: PackBleeds.Level?) -> String {
        switch level {
        case .spotting?: "spotting"
        case .light?: "light"
        case .medium?: "medium"
        case .heavy?: "heavy"
        case nil: "none logged"
        }
    }
}
