import Foundation
import HealthCore

// Caffeine and water: caffeine and your pill, how much caffeine, water goal.
// Copy moved here from a screen moves word for word.

extension HealthGuide {
    static let caffeineWater: [GuideArticle] = [.caffeineAmounts, .caffeineAndPill, .caffeineAtBedtime, .waterGoal]
}

/// Caffeine and water copy shared by a screen and its guide article, so
/// both say the same thing.
enum CaffeineWaterCopy {
    /// What to make of the daily limit (the ⓘ adds a line about the bar).
    static let dailyLimitForYou = "It's a ceiling, not a target: less is fine, and none is fine too. Some people feel shaky, anxious or get a racing heart on much less."

    /// The Caffeine summary's ⓘ (was beside the old ring).
    static let dailyLimit = Explanation(
        id: "caffeineDaily", title: "How much caffeine a day",
        meaning: "Up to \(CaffeineModel.dailyGuideMg) mg a day is generally fine for healthy adults; under \(CaffeineModel.lowerGuideMg) mg if you could be pregnant or are trying. About \(CaffeineModel.lowerGuideMg) mg in one go is the most that's generally fine at once.",
        forYou: dailyLimitForYou + " The bar shows how close today is to \(CaffeineModel.dailyGuideMg) mg.")

    /// Under the common drinks in More drinks.
    static let typicalAmounts = "Typical amounts. Coffee-shop coffee is stronger than home brewed, and energy drinks and pre-workouts vary a lot (150 to 300 mg), so check your label. For a different amount, use New caffeine drink."

    /// The Water summary's ⓘ (the daily goal).
    static let waterGoal = Explanation(
        id: "waterGoal", title: "Daily water goal",
        meaning: "How much you want to drink across the day. Bottles are counted with your own bottle size, which you can change in Bottle and goal.",
        forYou: "For women, US guidance is about 9 cups (74 oz) a day from drinks; food adds more. You need more if you\u{2019}re pregnant or breastfeeding, and on hot days and workout days. These are averages, not requirements: drink to thirst, and pale yellow pee usually means you\u{2019}re drinking enough. During long workouts, don\u{2019}t drink much more than you sweat out; far too much water can be dangerous.")

    /// Under the goal stepper when it's set over about 135 oz.
    static let highGoal = "Over about 135 oz (4 liters) a day is a lot for most women, and drinking far more than your body needs can be dangerous. Unless a doctor told you to, a lower goal is safer."
}

extension GuideArticle {
    /// The 400 and 200 mg guidance (the old hero ⓘ) and typical amounts
    /// (under the common drinks), word for word.
    static let caffeineAmounts = GuideArticle(
        id: "caffeineAmounts",
        title: "How much caffeine",
        summary: "The daily limit, the most at once, and what typical drinks hold.",
        body: [
            .paragraph(CaffeineWaterCopy.dailyLimit.meaning),
            .paragraph(CaffeineWaterCopy.dailyLimitForYou),
            .paragraph(CaffeineWaterCopy.typicalAmounts),
        ],
        keywords: ["400 mg", "200 mg", "pregnant", "coffee", "energy drink", "pre-workout", "espresso", "tea"])

    /// The cutoff ⓘ's half-life copy and its source, word for word.
    static let caffeineAndPill = GuideArticle(
        id: "caffeineAndPill",
        title: "Caffeine and your birth control",
        summary: "Why caffeine lasts longer on the combined pill, ring and patch.",
        body: [
            .paragraph(Topic.caffeineCutoff.explanation.forYou),
            .paragraph("The 7 hours on the pill comes from one small study (Abernethy & Todd, 1985), so treat it as a rough guide."),
        ],
        keywords: ["half-life", "pill", "ring", "patch", "estrogen", "cutoff"],
        methods: [.combinedPill, .ring, .patch])

    /// The bedtime ⓘ's "why 35 mg", word for word.
    static let caffeineAtBedtime = GuideArticle(
        id: "caffeineAtBedtime",
        title: "Caffeine at bedtime",
        summary: "Why the goal is under 35 mg left when you go to bed.",
        body: [
            .paragraph(Topic.caffeineLeft.explanation.meaning),
            .paragraph(Topic.caffeineLeft.explanation.forYou),
            .paragraph(Topic.caffeineLeft.explanation.howWeGotIt ?? ""),
        ],
        keywords: ["35 mg", "deep sleep", "cutoff", "Gardiner"])

    /// The Water goal card's guidance and cautions, word for word.
    static let waterGoal = GuideArticle(
        id: "waterGoal",
        title: "How much water",
        summary: "About 9 cups a day from drinks, and why more isn't always better.",
        body: [
            .paragraph("For women, US guidance is about 9 cups (74 oz) a day from drinks. Drinks like tea, milk and juice count too, and food adds more on top."),
            .paragraph(CaffeineWaterCopy.waterGoal.forYou),
            .heading("Catching up"),
            .paragraph("No need to catch up at once: spread it out, no more than about 34 oz an hour."),
            .callout(CaffeineWaterCopy.highGoal),
        ],
        keywords: ["hydration", "cups", "ounces", "liters", "goal", "bottle"])
}
