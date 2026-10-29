import Foundation
import HealthCore

/// The one-page summary for her pill visit (G1): her pill and when she
/// started it, missed pills (A1), bleeds by pack (A10), spotting, symptoms,
/// mood by pack day (B1) and any blood pressure in Apple Health. Plain
/// values; `VisitSummaryPage` lays them out.
struct VisitSummary {
    struct PackRow: Hashable {
        var dates: String
        /// Active pills with no dose logged (pack days).
        var missed: [Int]
        var bleedDays: Int
        var heaviest: String
        /// Active-pill days with spotting or bleeding.
        var activeSpotting: Int
        var isCurrent: Bool
    }
    struct SymptomRow: Hashable {
        var name: String
        var days: Int
        var inBreak: Int
    }
    struct MoodRow: Hashable {
        var title: String
        var active: Double?
        var breakDays: Double?
        /// "higher is better" or "higher is worse", for the reader.
        var scaleNote: String
    }

    var method: String
    var since: Date?
    var pillTime: String
    /// "Jul 5 – Oct 28, 2026".
    var range: String
    var packCount: Int
    var packs: [PackRow]
    var takenDays: Int
    var judgedDays: Int
    var symptoms: [SymptomRow]
    /// What stands out in her break weeks ("headaches", "lower mood").
    var pattern: [String]?
    var mood: [MoodRow]
    var moodChart: MoodByPackDay?
    var activeDays: Int
    var packLength: Int
    var breakName: String
    /// "118/76 mmHg", or nil when Apple Health has none.
    var bloodPressure: String?
    var made: Date
    var isExample: Bool

    var missedTotal: Int { packs.map(\.missed.count).reduce(0, +) }
}

extension AppModel {
    /// Packs on the summary: the last four finished, and the current one.
    static let visitPacks = 4

    /// The summary from what she's logged. Combined pill with a pack only.
    func visitSummary(bloodPressure: String?) -> VisitSummary? {
        guard let cal = packCalendar, let pack = pillPack else { return nil }
        let day = Calendar.current
        let current = cal.position(of: .now).pack
        let packs = finishedPacks.suffix(Self.visitPacks) + [current]
        let bleeds = Dictionary(uniqueKeysWithValues: PackBleeds.summarize(packFlows, packs: Array(packs), in: cal).map { ($0.pack, $0) })
        let firstDose = pillDoses.min().map(pillDay(for:))
        let latestDue = currentPillDay

        var taken = 0, judged = 0
        let rows: [VisitSummary.PackRow] = packs.reversed().map { p in
            var missed: [Int] = []
            for d in 1...cal.activeDays {
                let date = cal.date(pack: p, day: d)
                guard date < latestDue || (date == latestDue && isPillTaken(on: date)) else { continue }
                guard let firstDose, date >= firstDose else { continue }
                judged += 1
                if isPillTaken(on: date) { taken += 1 } else { missed.append(d) }
            }
            let b = bleeds[p]
            return VisitSummary.PackRow(dates: packDateRange(p), missed: missed, bleedDays: b?.bleedDays ?? 0,
                                        heaviest: b?.heaviest.map { Self.flowWord($0) } ?? "\u{2013}",
                                        activeSpotting: b?.activeDays ?? 0, isCurrent: p == current)
        }

        // Symptoms over these packs, with how many fell on break days.
        let start = cal.start(ofPack: packs.first ?? current)
        var symptomDays: [String: Set<Date>] = [:], breakDays: [String: Set<Date>] = [:]
        for entry in store.data.symptomLog where entry.date >= start {
            let d = day.startOfDay(for: entry.date)
            let inBreak = cal.isBreak(day: cal.position(of: d).day)
            for s in entry.symptoms {
                symptomDays[s, default: []].insert(d)
                if inBreak { breakDays[s, default: []].insert(d) }
            }
        }
        let symptoms = symptomDays.map { VisitSummary.SymptomRow(name: $0.key, days: $0.value.count, inBreak: breakDays[$0.key]?.count ?? 0) }
            .sorted { ($0.days, $1.name) > ($1.days, $0.name) }

        let mood: [VisitSummary.MoodRow] = MoodScale.allCases.compactMap { scale in
            guard let data = moodByPackDay(scale), !data.points.isEmpty else { return nil }
            let split = data.split(activeDays: cal.activeDays)
            return VisitSummary.MoodRow(title: Self.moodTitle(scale), active: split.active, breakDays: split.breakDays,
                                        scaleNote: scale == .mood ? "1 very low, 5 very good" : "1 none, 5 a lot")
        }

        let style: Date.FormatStyle = .dateTime.month(.abbreviated).day().year()
        return VisitSummary(
            method: "Combined pill \u{00B7} \(pack.activeDays) active" + (pack.hasBreak ? " + \(pack.packLength - pack.activeDays) break" : ", no break"),
            since: pillHistorySince, pillTime: Clock.format(store.data.pillTime),
            range: "\(start.formatted(style)) \u{2013} \(Date.now.formatted(style))", packCount: packs.count,
            packs: rows, takenDays: taken, judgedDays: judged, symptoms: Array(symptoms.prefix(6)),
            pattern: breakWeekPattern.flatMap { $0.isEmpty ? nil : $0 }, mood: mood, moodChart: moodByPackDay(.mood),
            activeDays: pack.activeDays, packLength: pack.packLength, breakName: packBreakName.lowercased(),
            bloodPressure: bloodPressure, made: .now, isExample: DemoMode.isOn)
    }

    /// Her latest blood pressure in Apple Health over the past year, as
    /// "118/76 mmHg". The example on demo data.
    func latestBloodPressure() async -> String? {
        if DemoMode.isOn { return "112/72 mmHg" }
        guard HealthKitService.isAvailable,
              let sys = try? await health.latest(.bloodPressureSystolic, unit: .millimeterOfMercury(), days: 365),
              let dia = try? await health.latest(.bloodPressureDiastolic, unit: .millimeterOfMercury(), days: 365) else { return nil }
        return "\(Int(sys.rounded()))/\(Int(dia.rounded())) mmHg"
    }
}
