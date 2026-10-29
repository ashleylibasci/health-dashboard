import Foundation
import HealthCore

/// What she logged that changes something for her pill: being sick on
/// active pills (H-A7) and spotting on active pills (H-A8).
extension AppModel {
    /// Symptoms that can stop the pill being absorbed (CDC US SPR 2024).
    static let pillSickSymptoms: Set<String> = ["Vomiting", "Diarrhea"]
    /// Standard drinks the evening before that make next-morning nausea
    /// worth the same note (the morning-after line, D1).
    static let pillBigNightDrinks = AlcoholClearance.morningAfterDrinks

    enum PillSickTrigger: Hashable {
        /// Vomiting or diarrhea logged today or yesterday on an active pill day.
        case sick
        /// Nausea this morning after 4+ standard drinks last night.
        case bigNight
    }

    /// Combined pill only, while it's recent enough to act on.
    var pillSickTrigger: PillSickTrigger? {
        guard store.birthControl == .combinedPill, let pack = pillPack else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return nil }
        let recent = store.data.symptomLog.filter { $0.date >= yesterday && pack.isPillDay($0.date) }
        if recent.contains(where: { !Self.pillSickSymptoms.isDisjoint(with: $0.symptoms) }) { return .sick }
        let nauseaToday = recent.contains { cal.isDateInToday($0.date) && $0.symptoms.contains("Nausea") }
        if nauseaToday, standardDrinks(beforeWakeDay: appDayDate) >= Self.pillBigNightDrinks { return .bigNight }
        return nil
    }

    // MARK: Spotting on active pills (H-A8)

    /// Spotting logged today or yesterday on an active pill day: breakthrough
    /// bleeding, not a period (and never a period start).
    var spottingOnActivePills: Bool {
        guard store.birthControl == .combinedPill, let pack = pillPack else { return false }
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now)) else { return false }
        return store.data.flowLog.contains { $0.flow == .spotting && $0.date >= yesterday && pack.isPillDay($0.date) }
    }

    /// Finished packs with spotting on active pill days, of the last three,
    /// counting only packs after her first 3 months on this pill (before
    /// that it's the usual settling in).
    var spottingPacksAfterThreeMonths: Int {
        guard let since = pillHistorySince, let cal = packCalendar,
              let threeMonths = Calendar.current.date(byAdding: .day, value: 90, to: since) else { return 0 }
        let packs = finishedPacks.suffix(3).filter { cal.start(ofPack: $0) >= threeMonths }
        let spotted = Set(store.data.flowLog.compactMap { entry -> Int? in
            guard entry.flow == .spotting else { return nil }
            let at = cal.position(of: entry.date)
            return cal.isBreak(day: at.day) ? nil : at.pack
        })
        return packs.filter(spotted.contains).count
    }

    /// Spotting has kept happening past month 3: in 2 of her last 3 packs.
    var spottingKeepsHappening: Bool { spottingPacksAfterThreeMonths >= 2 }
}
