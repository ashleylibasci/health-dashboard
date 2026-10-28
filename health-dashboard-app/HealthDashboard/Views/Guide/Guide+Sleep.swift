import Foundation

// Sleep: trouble sleeping (insomnia, CBT-I, restless legs, sleep and your
// period). Clocks changing keeps its own screen.
// Copy moved here from a screen moves word for word.

extension HealthGuide {
    static let sleep: [GuideArticle] = [.troubleSleeping]
}

extension GuideArticle {
    /// The Sleep tab's "Trouble sleeping?" card, word for word (Park 13).
    static let troubleSleeping = GuideArticle(
        id: "troubleSleeping",
        title: "Trouble sleeping",
        summary: "Insomnia, restless legs, and when to ask for help.",
        body: [
            .paragraph("Trouble falling or staying asleep 3 or more nights a week, for months? That's insomnia, and it's very treatable. CBT-I, a short program that changes sleep habits and thoughts, is the first-line treatment, and many campuses offer it. Ask your campus health or counseling center."),
            .paragraph("An urge to move your legs at night can be restless legs, which is linked to low iron. Sleep that gets much worse every month before your period is worth mentioning to a clinician too."),
        ],
        keywords: ["insomnia", "CBT-I", "restless legs", "iron", "can't sleep", "period"])
}
