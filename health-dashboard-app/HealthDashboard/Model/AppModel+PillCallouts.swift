import Foundation
import HealthCore

/// What she logged that changes something for her pill: being sick on
/// active pills (H-A7).
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
}
