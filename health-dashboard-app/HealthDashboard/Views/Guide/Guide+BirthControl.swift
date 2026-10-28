import Foundation
import HealthCore

// Birth control: missed or late, medicines that change how it works, and
// what the app doesn't show on a pack method. One article per method
// (`methods` set), so the guide and the Cycle screen's safety rows show
// only hers. The wording lives in `CycleCare` (CycleSafety.swift), shared
// with the Birth control Learn page.
// Copy moved here from a screen moves word for word.

extension HealthGuide {
    static let birthControl: [GuideArticle] =
        GuideArticle.missedDoseArticles + GuideArticle.medicineArticles + GuideArticle.notShownArticles
}

extension GuideArticle {
    /// "Missed or late pill?" for each method with something to miss, and
    /// for pack methods the no-bleed advice that sat under Cycle's status.
    static let missedDoseArticles: [GuideArticle] = CycleCare.missedDoseMethods.map { method in
        GuideArticle(
            id: "missedDose-\(method.rawValue)",
            title: CycleCare.missedDoseTitle(method),
            summary: "What to do, by how late you are.",
            body: [.bullets(CycleCare.missedDoseRules(method))]
                + (method.hasBreakWeek ? [.paragraph(CycleCare.noBleedAdvice(method))] : []),
            source: CycleCare.missedDoseSource,
            keywords: ["missed", "late", "forgot", "backup", "condoms", "emergency contraception", "vomiting"],
            methods: [method])
    }

    /// Medicines that can make her method work less well.
    static let medicineArticles: [GuideArticle] = CycleCare.medicineMethods.map { method in
        GuideArticle(
            id: "medicines-\(method.rawValue)",
            title: CycleCare.medicinesTitle(method),
            summary: "Which ones make it work less well.",
            body: [.bullets(CycleCare.medicineLines(method))],
            keywords: ["medicine", "antibiotics", "rifampin", "seizure", "St John's wort", "lamotrigine", "tirzepatide"],
            methods: [method])
    }

    /// Cycle's "Not shown on the combined pill" and "Still tracked" cards,
    /// word for word, for the pill, ring and patch.
    static let notShownArticles: [GuideArticle] = [BirthControl.combinedPill, .ring, .patch].map { method in
        GuideArticle(
            id: "notShown-\(method.rawValue)",
            title: "Not shown on the \(method.inSentence)",
            summary: "And what\u{2019}s still tracked.",
            body: [
                .bullets(["Ovulation estimate", "Fertile days", "Luteal heart-rate bump", "Period countdown"]),
                .paragraph("Your \(method.inSentence) stops your body from releasing an egg each month, so these natural-cycle changes don't happen to you and the app never predicts them."),
                .heading("Still tracked"),
                .bullets([
                    "Temperature running a bit higher and flat. Normal on your method.",
                    "Withdrawal bleeds and spotting, from what you log.",
                    "Headaches, mood and other symptoms you log, by date. Some people notice headaches in the break week.",
                ]),
            ],
            keywords: ["ovulation", "fertile", "period", "luteal", "withdrawal bleed"],
            methods: [method])
    }

    static func missedDose(for method: BirthControl?) -> GuideArticle? {
        missedDoseArticles.first { $0.applies(to: method) }
    }

    static func medicines(for method: BirthControl?) -> GuideArticle? {
        medicineArticles.first { $0.applies(to: method) }
    }

    static func notShown(for method: BirthControl?) -> GuideArticle? {
        notShownArticles.first { $0.applies(to: method) }
    }
}
