import Foundation

// Alcohol: what one drink is, alcohol poisoning signs and what to do, timing tips.
// Copy moved here from a screen moves word for word.

extension HealthGuide {
    static let alcohol: [GuideArticle] = [.alcoholPoisoning, .standardDrink, .alcoholTips]
}

/// Alcohol copy shared by a screen and its guide article.
enum AlcoholCopy {
    /// The safety note's full text, behind its one-line callout.
    static let poisoningSigns = "4 or more drinks in an evening is a lot for most women, and blood alcohol keeps rising for a while after the last one. Signs of alcohol poisoning: confusion, throwing up, slow or uneven breathing, pale or bluish skin, or can\u{2019}t be woken. If you see any, call 911. Don\u{2019}t leave a friend alone to sleep it off; keep her on her side."

    /// "What helps most" on the Alcohol screen.
    static let tips = [
        "Finish your last drink 3 or more hours before bed, and have a glass of water between drinks. A standard drink takes most women about 2 hours to clear, and nothing speeds it up: not coffee, water or sleep. Cocktails are often 2 or more.",
        "Energy drinks and alcohol in the same evening can hide how drunk you feel, so they\u{2019}re best kept apart.",
    ]
}

extension GuideArticle {
    /// The safety note from the Log tab and the Alcohol screen, word for word.
    static let alcoholPoisoning = GuideArticle(
        id: "alcoholPoisoning",
        title: "Alcohol poisoning signs",
        summary: "What to look for after a lot of drinks, and what to do.",
        body: [.callout(AlcoholCopy.poisoningSigns)],
        keywords: ["911", "drunk", "throwing up", "passed out", "friend", "binge"],
        links: [.call("911")])

    /// The standard-drink line that sat on the Log tab's alcohol card, and
    /// the ⓘ's note on why women feel it more, word for word.
    static let standardDrink = GuideArticle(
        id: "standardDrink",
        title: "What one drink is",
        summary: "A glass of wine, a beer or a shot, and why a cocktail is often two.",
        body: [
            .paragraph("One drink is 5 oz of wine, 12 oz of 5% beer or seltzer, or a 1.5 oz shot. A cocktail or big pour is often 2 or more."),
            .paragraph(Topic.alcohol.explanation.howWeGotIt ?? ""),
        ],
        keywords: ["standard drink", "wine", "beer", "seltzer", "shot", "cocktail"])

    /// "What helps most" from the Alcohol screen, word for word.
    static let alcoholTips = GuideArticle(
        id: "alcoholTips",
        title: "Alcohol and sleep: what helps",
        summary: "Timing your last drink, water, and what doesn't speed it up.",
        body: AlcoholCopy.tips.map { .paragraph($0) },
        keywords: ["sleep", "water", "energy drink", "hangover"])
}
