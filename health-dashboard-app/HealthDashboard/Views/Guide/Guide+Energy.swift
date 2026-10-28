import Foundation

// Energy: articles for the Energy, Your week, Body clock and exam screens.
// Copy moved here from a screen moves word for word.

extension HealthGuide {
    static let energy: [GuideArticle] = [.energyThroughTheDay, .bodyClockTypes, .examWeek]
}

extension GuideArticle {
    /// The energy curve's ⓘ and each zone's meaning and action, as the
    /// Energy screen's readout used to show them in full.
    static let energyThroughTheDay = GuideArticle(
        id: "energyThroughTheDay",
        title: "Your energy through the day",
        summary: "What the curve predicts, and what each part of the day is good for.",
        body: [
            .paragraph("A prediction of how alert you'll feel at each time of day, from 0 (running on empty) to 100 (fully switched on). It comes from when and how long you slept and your body clock."),
            .paragraph("Plan hard work for the high parts and easy things for the low parts. Drag along the curve to see what each moment means."),
            .heading("Grogginess"),
            .paragraph("The foggy, just-woke-up feeling while your brain switches on. Skip big decisions. Daylight, water and moving around clear it faster."),
            .heading("Morning peak"),
            .paragraph("Your sharpest focus of the day. Save it for your hardest studying: problem sets, writing, anything that needs focus."),
            .heading("Afternoon dip"),
            .paragraph("A natural energy drop, mostly from your body clock. It happens even without lunch, though a big meal can add to it. Good time for easy tasks or a walk. A 20-minute nap early in the dip is fine."),
            .heading("Second wind"),
            .paragraph("Your body clock pushes back against the day's tiredness, so your energy lifts again. Good for group study or seeing friends. Wrap up anything intense a couple of hours before bed."),
            .heading("Wind-down"),
            .paragraph("About 2 hours before you usually fall asleep, your body starts making its own sleep hormone (melatonin, not pills). Dim the lights, put screens down and do something calm."),
            .heading("Sleep window"),
            .paragraph("The hour before you usually fall asleep. Your body's own sleep hormone has been rising for a while (not about melatonin pills), so falling asleep tends to come easiest now. Aim to be in bed in this window. Falling asleep is usually easiest now; much later and you may lie awake. It's an estimate from your usual sleep times."),
            .heading("Between the zones"),
            .bullets([
                "Warming up: the just-woke-up fog has cleared and your focus is building toward your peak.",
                "Coming off your peak: still fairly sharp, but drifting down toward the afternoon dip.",
                "Climbing out of the dip: your energy is coming back up toward your second wind.",
                "Evening: energy slowly fades as the day's tiredness catches up with you.",
                "Past your sleep window: your body expected to be asleep by now. Bright light and screens this late push your body clock later, so tomorrow morning feels harder.",
            ]),
        ],
        keywords: ["energy curve", "peak", "dip", "focus", "nap", "melatonin", "grogginess", "second wind"])

    /// The Body clock screen's type descriptions and its "What can shift
    /// it" advice, word for word.
    static let bodyClockTypes = GuideArticle(
        id: "bodyClockTypes",
        title: "Body clock types",
        summary: "Early bird to night owl, why it's later at your age, and what shifts it.",
        body: [
            .bullets([
                "Very early: Your body likes to sleep and wake much earlier than most people.",
                "Moderate morning: Your body leans toward earlier nights and earlier mornings.",
                "Intermediate: Right in the middle: not an early bird, not a night owl.",
                "Moderate evening: Your body leans toward later nights and later mornings than most people. Very common at your age.",
                "Definite evening: Your body clearly prefers late nights and late mornings. Common in your late teens and early twenties.",
                "Very late: Your body runs much later than most people's, so early mornings feel especially hard.",
            ]),
            .paragraph("Being an evening type isn't laziness; it's how your body is built right now."),
            .heading("What can shift it"),
            .paragraph("Morning daylight: the strongest signal your clock gets. Time outside before noon, day after day, moves your peak earlier."),
            .paragraph("A steady wake time: getting up within an hour of your school-day time on weekends anchors the clock."),
            .paragraph("A smaller weekend shift: keeping weekend sleep within an hour of school nights protects Monday mornings."),
        ],
        keywords: ["chronotype", "night owl", "early bird", "evening type", "morning type", "weekend shift", "social jet lag"])

    /// Exam-week mode's "Why it matters" and "Feeling overwhelmed?" cards,
    /// word for word (without the crisis line, Ashley's decision Oct 28).
    static let examWeek = GuideArticle(
        id: "examWeek",
        title: "Sleep and exam week",
        summary: "Why sleep beats one more hour of review, and where to turn when it's too much.",
        body: [
            .heading("Short nights cost recall"),
            .paragraph("After a short night, memory and focus drop. Sleep is when what you studied gets stored, so an all-nighter takes back more than it gives."),
            .paragraph("Sleep all week, especially the nights after you study, is what makes it stick."),
            .heading("Up all night? Don't drive"),
            .paragraph("After an all-nighter or a very short night, driving is about as risky as driving drunk. Get a ride or take the bus."),
            .heading("Feeling overwhelmed?"),
            .paragraph("Exam weeks are hard, and you don't have to get through them alone. Your campus counseling center can help. If you're sick, dealing with something at home or just can't keep up, your dean of students or accessibility office can talk to you about extensions or a make-up."),
        ],
        keywords: ["exam", "study", "all-nighter", "finals", "midterm", "counseling", "extension"])
}
