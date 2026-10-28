import Foundation

// Help now: always first in the guide and never hidden by search. Call
// and text buttons sit right under each title. To add: Call 911 (the "Call
// 911 now" care tier) and campus counseling.
// Copy moved here from a screen moves word for word.

extension HealthGuide {
    static let helpNow: [GuideArticle] = [.crisisLine]
}

extension GuideArticle {
    /// The 988 Lifeline, as on `CrisisLineCard`.
    static let crisisLine = GuideArticle(
        id: "crisisLine",
        title: "988 Suicide & Crisis Lifeline",
        summary: "Call or text 988, free and confidential, any time (US).",
        body: [
            .paragraph("Free and confidential, any time, if your mood gets very low or you think about hurting yourself. 988 works in the US; elsewhere, call your local emergency number."),
        ],
        keywords: ["988", "crisis", "suicide", "lifeline", "mood", "help"],
        links: [.call("988"), .text("988")])
}
