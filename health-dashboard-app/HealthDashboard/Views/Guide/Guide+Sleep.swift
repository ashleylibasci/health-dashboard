import Foundation

// Sleep: how the best sleep times are worked out, and trouble sleeping
// (insomnia, CBT-I, restless legs, sleep and your period). Clocks changing
// keeps its own screen.
// Copy moved here from a screen moves word for word.

extension HealthGuide {
    static let sleep: [GuideArticle] = [.bestSleepTimes, .troubleSleeping]
}

extension GuideArticle {
    /// How the Sleep tab's best sleep times are worked out (Park's method).
    static let bestSleepTimes = GuideArticle(
        id: "bestSleepTimes",
        title: "Your best sleep times",
        summary: "Where your bed-by and wake times come from, and how sure they are.",
        body: [
            .heading("Where the times come from"),
            .paragraph("Bed by starts from the sleep you need and the latest you need to be up, plus the few minutes it takes you to fall asleep. Once your body clock is known (at least 4 free nights and 8 school nights), it can move bed by earlier, never later. Up at is the end of a sleep cycle just before your up-by time, or up-by itself."),
            .paragraph("After 28 school nights of your own, the app compares your earlier, middle and later nights by how your body did the next morning: HRV, resting heart rate, how much of your time in bed you slept, and your morning check-in. Sleep length is taken out first, so a later night isn't marked down just for being shorter."),
            .heading("Which nights count"),
            .bullets([
                "Nights with an alarm. Free nights mix bedtime with sleeping in, so they're used for your body clock instead.",
                "Not nights after drinks, during an exam stretch, while you logged symptoms, or the night the clocks change.",
                "At least 4 hours asleep, with HRV or resting heart rate the next morning.",
            ]),
            .heading("What it can and can't tell"),
            .paragraph("With about 20 nights in each group, only fairly big differences show up. Smaller ones read as no clear difference, and then keeping your bedtime about the same each night is the best bet."),
            .paragraph("The Watch's sleep start is good to about 15 minutes, so the window is 30 minutes wide and only moves in 15-minute steps, at most 45 minutes earlier. It never moves later than the bedtime that covers your need, and it never moves your wake time."),
            .paragraph("Everything is compared with your own usual. It's a pattern in your data, not proof that the time of night caused it."),
            .heading("How sure it is"),
            .bullets([
                "Learning: from your sleep need and body clock, until 28 school nights.",
                "Early read: a pattern from 28 to 55 nights. It counts half and could change.",
                "Fairly sure: 56 nights or more, in both your older and newer nights, with more than one measure agreeing.",
            ]),
        ],
        keywords: ["bedtime", "best bedtime", "wake time", "HRV", "sleep window", "regular"])

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
