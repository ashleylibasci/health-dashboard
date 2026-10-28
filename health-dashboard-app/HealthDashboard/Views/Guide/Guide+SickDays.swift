import Foundation
import HealthCore

// Sick days: being sick on your method. The sick check links here (one row,
// only while she may be sick); the Cycle screen's safety rows too.
// Copy moved here from a screen moves word for word.

extension HealthGuide {
    static let sickDays: [GuideArticle] = [.sickOnPill, .sickOnRingOrPatch]
}

extension GuideArticle {
    /// The sick check's "Being sick on the pill" card, word for word (CDC US
    /// SPR 2024, round 4, Moreno F3). Only the combined pill is affected by
    /// vomiting or diarrhea.
    static let sickOnPill = GuideArticle(
        id: "sickOnPill",
        title: "Being sick on the pill",
        summary: "Throwing up, diarrhea and antibiotics.",
        body: [
            .bullets([
                "Throwing up or bad diarrhea for less than 2 days (48 hours): keep taking your pills as usual. You don\u{2019}t need an extra pill or condoms.",
                "For 2 days or more: keep taking your pills if you can, and use condoms (or skip sex) until you\u{2019}ve taken an active pill 7 days in a row after you\u{2019}re better.",
                "If that happens in the last week of active pills, skip the break and start your next pack straight away.",
                "If it happens in the first week of a pack and you had sex in the last 5 days, ask a pharmacist about emergency contraception.",
                "Most antibiotics don\u{2019}t affect the pill. Rifampin does, so tell your pharmacist you\u{2019}re on the pill with any new medicine.",
            ]),
        ],
        source: "From the CDC\u{2019}s 2024 birth control guidance.",
        keywords: ["vomiting", "throwing up", "diarrhea", "antibiotics", "rifampin", "stomach bug"],
        methods: [.combinedPill])

    /// The sick check's note for the ring and patch, word for word.
    static let sickOnRingOrPatch = GuideArticle(
        id: "sickOnRingOrPatch",
        title: "Being sick on the ring or patch",
        summary: "Throwing up or diarrhea doesn\u{2019}t affect it.",
        body: [
            .paragraph("Throwing up or diarrhea doesn\u{2019}t affect it: the hormones don\u{2019}t go through your stomach. Most antibiotics don\u{2019}t either. Rifampin does, so tell your pharmacist about your birth control with any new medicine."),
        ],
        keywords: ["vomiting", "throwing up", "diarrhea", "antibiotics", "rifampin", "stomach bug"],
        methods: [.ring, .patch])

    /// Being sick on her method, if her method has an article.
    static func sickOnMethod(for method: BirthControl?) -> GuideArticle? {
        [sickOnPill, sickOnRingOrPatch].first { $0.applies(to: method) }
    }
}
