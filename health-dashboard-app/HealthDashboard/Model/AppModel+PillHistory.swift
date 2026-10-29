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

    // MARK: Break-week pattern (H-A4)

    /// What stands out in her last three break weeks, as words ("headaches",
    /// "lower mood"), strongest first; nil before three finished packs, empty
    /// when nothing does.
    var breakWeekPattern: [String]? {
        guard let cal = packCalendar else { return nil }
        let day = Calendar.current
        var symptoms: [Date: Set<String>] = [:]
        for entry in store.data.symptomLog {
            symptoms[day.startOfDay(for: entry.date), default: []].formUnion(entry.symptoms)
        }
        var awake: [Date: Double] = [:]
        for c in store.data.checkIns { awake[AppDay.day(containing: c.date)] = Double(c.awake) }
        func scores(_ scale: MoodScale) -> [Date: Double] { moodByDay(scale).mapValues(Double.init) }
        let found = BreakWeekPattern.find(
            symptoms: symptoms,
            scores: [.init(name: "lower mood", byDay: scores(.mood), higherIsWorse: false),
                     .init(name: "more anxiety", byDay: scores(.anxiety), higherIsWorse: true),
                     .init(name: "more irritability", byDay: scores(.irritability), higherIsWorse: true),
                     .init(name: "feeling less rested", byDay: awake, higherIsWorse: false)],
            packs: finishedPacks, in: cal)
        return found.map { Array($0.prefix(3)).map(Self.patternWord) }
    }

    /// "Headaches, cramps and lower mood show up in your break weeks."
    var breakWeekPatternLine: String? {
        guard let words = breakWeekPattern, let first = words.first else { return nil }
        let list = words.count == 1 ? first
            : words.dropLast().joined(separator: ", ") + " and " + (words.last ?? "")
        return list.prefix(1).uppercased() + list.dropFirst() + " show up in your \(breaksPhrase)."
    }

    /// "break weeks", or "break days" on a 24 + 4 pack.
    var breaksPhrase: String { packBreakName == "Break days" ? "break days" : "break weeks" }

    /// A logged symptom as it reads in a sentence.
    private static func patternWord(_ name: String) -> String {
        switch name {
        case "Headache": "headaches"
        case "Fatigue": "tiredness"
        default: name.lowercased()
        }
    }
}
