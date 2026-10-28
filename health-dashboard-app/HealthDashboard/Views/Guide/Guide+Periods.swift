import Foundation
import HealthCore

// Periods and cycle care: eating enough for your training, and bleeding
// that needs checking on a method that changes bleeding. Heavy bleeding
// and 90 days without a period stay one-line prompts on the screens while
// they're true. The wording lives in `CycleCare` (CycleSafety.swift).
// Copy moved here from a screen moves word for word.

extension HealthGuide {
    static let periods: [GuideArticle] = [.eatingEnoughPack, .eatingEnoughMethod, .bleedingCheckIUD, .bleedingCheckImplant]
}

extension GuideArticle {
    /// Cycle's and Fitness's under-fuelling note for the pill, ring and
    /// patch (Ruiz F2): said once, here.
    static let eatingEnoughPack = GuideArticle(
        id: "eatingEnoughPack",
        title: "Eating enough for your training",
        summary: "What to watch for on your method.",
        body: [.paragraph(CycleCare.packBleedCantShowFuel)],
        keywords: ["RED-S", "fuel", "under-fuelling", "training", "injuries", "bone"],
        methods: [.combinedPill, .ring, .patch])

    /// The same note for methods that change bleeding without a break.
    static let eatingEnoughMethod = GuideArticle(
        id: "eatingEnoughMethod",
        title: "Eating enough for your training",
        summary: "What to watch for on your method.",
        body: [.paragraph(CycleCare.methodBleedCantShowFuel)],
        keywords: ["RED-S", "fuel", "under-fuelling", "training", "injuries", "bone"],
        methods: [.miniPill, .hormonalIUD, .implant, .shot])

    /// Cycle's "When to get bleeding checked" card on the hormonal IUD,
    /// word for word (Okafor F, H).
    static let bleedingCheckIUD = GuideArticle(
        id: "bleedingCheckIUD",
        title: "When to get bleeding checked",
        summary: "Bleeding that needs a check, and heavy bleeding.",
        body: [
            .paragraph(CycleCare.bleedingRedFlags),
            .paragraph(CycleCare.heavyBleeding),
            .callout(CycleCare.heavyBleedingUrgent),
        ],
        keywords: ["bleeding", "spotting", "heavy", "STI", "pregnancy test"],
        methods: [.hormonalIUD])

    /// The same card on the implant and shot, with its extra line.
    static let bleedingCheckImplant = GuideArticle(
        id: "bleedingCheckImplant",
        title: "When to get bleeding checked",
        summary: "Bleeding that needs a check, and heavy bleeding.",
        body: [
            .paragraph(CycleCare.bleedingRedFlags),
            .paragraph(CycleCare.heavyBleeding),
            .paragraph("Bleeding that lasts more than 2 weeks or comes with a lot of pain, or you think you could be pregnant: check in with a doctor too."),
            .callout(CycleCare.heavyBleedingUrgent),
        ],
        keywords: ["bleeding", "spotting", "heavy", "STI", "pregnancy test"],
        methods: [.implant, .shot])

    static func eatingEnough(for method: BirthControl?) -> GuideArticle? {
        [eatingEnoughPack, eatingEnoughMethod].first { $0.applies(to: method) }
    }

    static func bleedingCheck(for method: BirthControl?) -> GuideArticle? {
        [bleedingCheckIUD, bleedingCheckImplant].first { $0.applies(to: method) }
    }
}
