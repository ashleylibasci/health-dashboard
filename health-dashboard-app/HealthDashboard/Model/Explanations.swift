import Foundation

/// Plain-language explanations for every term the app shows.
/// `meaning` says what it is, `forYou` says what to do with it, and
/// `howWeGotIt` (shown only behind "How we got this number") holds the method.
struct Explanation: Identifiable, Hashable {
    let id: String
    let title: String
    let meaning: String
    let forYou: String
    var howWeGotIt: String? = nil
}

enum Topic: String, CaseIterable, Identifiable {
    case melatonin, grogginess, morningPeak, afternoonDip, secondWind, windDown
    case energyScore, energyBank, effort, daylight
    case sleepNeed, tonightNeed, sleepDebt, sleepStages, deep, rem, core, awake, regularity, weekendShift
    case smartAlarm, sleepCycle, bestWakeWindow
    case recovery, hrv, restingHR, stress, breathingRate, wristTemp, illness, fitnessAge, calories
    case bodyClock, socialJetlag
    case caffeineCutoff, caffeineLeft, coffeeNap, cutoffTest
    case period, follicular, ovulation, luteal, pillPack, withdrawalBleed
    case timeChange, alcohol, lateNight

    var id: String { rawValue }

    var explanation: Explanation {
        switch self {
        case .melatonin: Explanation(id: id, title: "Melatonin window",
            meaning: "Melatonin is a hormone your own body makes at night to get you ready for sleep. It usually starts rising about 2 hours before you normally fall asleep and stays up through the night. It has nothing to do with taking melatonin pills.",
            forYou: "This window is the hour before you usually fall asleep. By then melatonin has been rising for a while, so it's usually the easiest time to drift off instead of lying awake. Bright screens and overhead lights can hold melatonin back, so dim them in the couple of hours before if you can.",
            howWeGotIt: "In studies, melatonin starts rising (in dim light) about 2 hours before people's usual time of falling asleep, though this varies from person to person. Your Watch can't measure melatonin, so this is an estimate: the window is the hour ending around the time you usually fall asleep on school nights, from your Apple Watch sleep data (or your planned bedtime until there are nights to learn from). The 15 minutes before it are your wind-down.")
        case .grogginess: Explanation(id: id, title: "Grogginess",
            meaning: "The foggy, slow feeling right after you wake up. Scientists call it sleep inertia. Your brain takes a while to fully switch on, especially if you woke from deep sleep.",
            forYou: "Avoid big decisions, tests or driving if you can during this time. Daylight, water and moving around clear it faster. Waking at the end of a sleep cycle, which the smart alarm aims for, makes it shorter.",
            howWeGotIt: "Grogginess fades over 20 to 60 minutes. We estimate it from whether you woke from light or deep sleep.")
        case .morningPeak: Explanation(id: id, title: "Morning peak",
            meaning: "The part of the day when your focus and alertness are naturally highest.",
            forYou: "Save your hardest thinking for this window: studying, problem sets, writing. Try not to spend it on email or scrolling.",
            howWeGotIt: "Your energy curve combines how long you've been awake (sleep pressure builds through the day) with your body clock's daily rhythm, timed from when you usually sleep.")
        case .afternoonDip: Explanation(id: id, title: "Afternoon dip",
            meaning: "A natural drop in energy in the early afternoon. Almost everyone has one. It comes mostly from your body clock, so it happens even if you skip lunch, though a big meal can make it feel stronger.",
            forYou: "Plan easy tasks here. Daylight or a short break helps. A short nap (20 minutes max) early in the dip is fine, but caffeine after your cutoff will cost you sleep tonight.")
        case .secondWind: Explanation(id: id, title: "Second wind",
            meaning: "A late-afternoon or evening rise in energy, when your body clock pushes back against the tiredness that has built up all day.",
            forYou: "A good time to be active or study with friends. Wrap up anything intense a couple of hours before bed so you can wind down.")
        case .windDown: Explanation(id: id, title: "Wind-down",
            meaning: "The stretch just before your melatonin window, when it helps to start slowing down.",
            forYou: "Dim the lights, put screens down or on night mode, and do something calm. It makes falling asleep much easier.")
        case .energyScore: Explanation(id: id, title: "Energy score",
            meaning: "How much energy your body is predicted to have over the 16 hours after you wake, from 0 to 100. It's a different number from energy left, which is a battery for right now. Your usual is shown next to it. Until there are 7 days of your own, that's a starting point of 74: a fixed middle-of-the-range value the app begins from, not anyone's measured average.",
            forYou: "Below usual means today will feel harder than normal. It's mostly driven by sleep debt and how rested your body is.",
            howWeGotIt: "We use the two-process model of sleep, the standard model sleep researchers use: sleep pressure that builds while you're awake and clears while you sleep, plus your body clock's daily rhythm. Sleep debt flattens your peaks.")
        case .energyBank: Explanation(id: id, title: "Energy left",
            meaning: "Think of it like a battery. It charges while you sleep and drains steadily while you're awake. It's a different number from your energy score, which rates the whole day.",
            forYou: "The percentage tells you how much you have left now and roughly how much you'll have at bedtime.",
            howWeGotIt: "It starts from how long you slept against your need, your sleep debt and your HRV this morning, then drains with the hours you've been awake.")
        case .effort: Explanation(id: id, title: "Effort target",
            meaning: "How much physical activity makes sense for you today, based on how recovered you are.",
            forYou: "On low-recovery days, aim for the lower end. On good days you can push harder.")
        case .daylight: Explanation(id: id, title: "Daylight",
            meaning: "Minutes your Apple Watch measured you in daylight today.",
            forYou: "Morning daylight is the strongest signal for setting your body clock. 20 minutes or more before noon makes it easier to feel awake in the morning and sleepy at night.")
        case .sleepNeed: Explanation(id: id, title: "Your sleep need",
            meaning: "How much sleep your body actually needs each night to feel and work its best. Everyone is different: some people need 7 hours, some need 9.",
            forYou: "Aim to get at least this much most nights. Getting less builds up sleep debt, even if you feel fine.",
            howWeGotIt: "We look at three things from your own nights. 1) On nights with no alarm, once you've caught up, how long you naturally sleep. 2) The point where more sleep stops improving your next-day heart rate, HRV and energy. 3) How you felt in your morning check-ins, used only as a cross-check, because research shows people who sleep too little often say they feel fine while their bodies and performance are still affected (Van Dongen et al., 2003). With little data we start near the adult average of 8 hours and narrow it down as nights add up.")
        case .tonightNeed: Explanation(id: id, title: "Tonight's need",
            meaning: "Your usual sleep need, plus a little extra if you have sleep debt to pay back, are in the last week before a natural-cycle period, or the sick check thinks you may be fighting something off (30 minutes).",
            forYou: "This is the amount to aim for tonight.")
        case .sleepDebt: Explanation(id: id, title: "Sleep debt",
            meaning: "How much sleep you've missed compared with your need, over the last two weeks. Recent nights count most.",
            forYou: "Sleep debt flattens your energy peaks and deepens your dips. You don't have to pay it all back at once: tonight's need adds about a tenth of your debt (up to 45 minutes a night), so a big debt comes down over a week or two.")
        case .sleepStages: Explanation(id: id, title: "Sleep stages",
            meaning: "Through the night you cycle through light (core) sleep, deep sleep and REM sleep, about every 90 minutes, with brief wake-ups that are normal.",
            forYou: "Deep sleep comes mostly early in the night and REM mostly near morning, so going to bed late cuts deep sleep, and waking early cuts REM.")
        case .deep: Explanation(id: id, title: "Deep sleep",
            meaning: "The most restful stage, when your body repairs itself.",
            forYou: "Most of it happens in the first half of the night, so a consistent, not-too-late bedtime protects it. Alcohol reduces its quality.")
        case .rem: Explanation(id: id, title: "REM sleep",
            meaning: "The dreaming stage, important for memory and learning.",
            forYou: "Most REM happens in the last hours before you wake, so cutting your sleep short in the morning cuts REM, which matters before exams.")
        case .core: Explanation(id: id, title: "Core sleep",
            meaning: "Light sleep. It makes up about half the night and is the easiest stage to wake from.",
            forYou: "The smart alarm tries to wake you during core sleep so you feel less groggy.")
        case .awake: Explanation(id: id, title: "Awake",
            meaning: "Short wake-ups during the night. Most you won't remember.",
            forYou: "A few are completely normal. Lots of them can come from alcohol, caffeine, a warm room or stress.")
        case .regularity: Explanation(id: id, title: "Sleep regularity",
            meaning: "How consistent your bedtime and wake time are from night to night, from 0 to 100.",
            forYou: "Regular sleep times help your body clock know when to make you sleepy and alert. Keeping weekends within an hour of weekdays helps most.")
        case .weekendShift: Explanation(id: id, title: "Weekend shift",
            meaning: "How much later you sleep and wake on free days than on school nights.",
            forYou: "A big shift is like flying a time zone west every weekend and back every Monday, which is why Mondays feel rough.")
        case .smartAlarm: Explanation(id: id, title: "Smart alarm",
            meaning: "Instead of one fixed time, your Apple Watch gets a window (for example 7:52–8:25). It wakes you the first time you seem to be in light sleep in that window, or at the end of it at the latest.",
            forYou: "Waking from light sleep usually means less grogginess. The latest time is never later than when you need to be up.")
        case .sleepCycle: Explanation(id: id, title: "Sleep cycle",
            meaning: "One trip through light, deep and REM sleep. For most people a cycle takes about 80 to 110 minutes. The wake plan uses yours, measured from your nights once there are enough of them.",
            forYou: "Waking at the end of a cycle feels easier than waking in the middle of one.")
        case .bestWakeWindow: Explanation(id: id, title: "Your best wake window",
            meaning: "The time range where your past mornings went best, based on how you felt and your energy those days.",
            forYou: "When it fits your schedule, the app aims your wake time inside this window.")
        case .recovery: Explanation(id: id, title: "Recovery",
            meaning: "How ready your body is today, from 0 to 100, compared with your own usual.",
            forYou: "Lower than usual means your body is still catching up (from short sleep, stress, illness, alcohol or a hard workout). Take it easier; higher means it's a good day to push.",
            howWeGotIt: "Mostly from your HRV (from readings taken while you slept, once there are enough) and resting heart rate compared with your last 30 days, plus last night's sleep compared with your need. Whether a score counts as below or above usual depends on how much yours normally moves. Your usual is your own average once there are 7 days; before that the app compares with a starting point of 78, a fixed middle-of-the-range value, not anyone's measured average. (Sleep need takes longer, 14 nights, because it learns from how your body responds to different amounts of sleep.)")
        case .hrv: Explanation(id: id, title: "HRV (heart rate variability)",
            meaning: "The tiny variation in time between heartbeats. Higher than your usual generally means your body is relaxed and recovered; lower means it's under strain.",
            forYou: "Only compare HRV with your own usual, never with other people's. It naturally dips late in your cycle, after drinking and when you're getting sick.")
        case .restingHR: Explanation(id: id, title: "Resting heart rate",
            meaning: "Your heart rate when you're fully at rest, mostly measured while you sleep.",
            forYou: "A few beats above your usual can mean short sleep, stress, alcohol, getting sick, or the second half of a natural cycle (after ovulation, before your period).")
        case .stress: Explanation(id: id, title: "Stress",
            meaning: "How hard your body seems to be working when you're not moving: a raised heart rate and lower HRV while sitting still.",
            forYou: "Raised stress isn't bad on its own, but long stretches of it hurt sleep. A few minutes of slow breathing lowers it quickly. Hours you were asleep or working out aren't counted.")
        case .breathingRate: Explanation(id: id, title: "Breathing rate",
            meaning: "Breaths per minute while you sleep. It's very steady for most people.",
            forYou: "A rise of one breath a minute or more is one of the earliest signs of getting sick.")
        case .wristTemp: Explanation(id: id, title: "Wrist temperature",
            meaning: "How your skin temperature during sleep compares with your usual.",
            forYou: "Small ups and downs night to night are normal. If you have a natural cycle, it also rises about \(TempFormat.delta(0.3, signed: false)) after ovulation and falls before your period; on birth control that stops ovulation, it stays flatter. A rise well above your usual can mean you're fighting something off.")
        case .illness: Explanation(id: id, title: "Might be getting sick",
            meaning: "When several signals move together (resting heart rate up, HRV down, breathing rate and wrist temperature up), your body is often fighting something, sometimes a day before you feel it. A hard workout the day before (well above your own usual) or the second half of a natural cycle can move some of them too, so the app allows for those. When it can't tell which part of your cycle you're in, it doesn't assume one: no cycle allowance is made, and it tells you your cycle could be part of it.",
            forYou: "It's a guess, not a diagnosis. Extra sleep, fluids and an easy day help. See a doctor if you feel unwell.")
        case .fitnessAge: Explanation(id: id, title: "Fitness age",
            meaning: "The age of an average woman with your cardio fitness (VO2 max, measured by your Apple Watch during walks and runs).",
            forYou: "Brisk walks, runs or cycling a few times a week bring it down. It updates slowly, over weeks.")
        case .calories: Explanation(id: id, title: "Calories",
            meaning: "An estimate of the energy your body used today: resting energy just to keep you alive, plus active energy from moving.",
            forYou: "Watch estimates can be off by 10–20%. It's useful for trends, not exact numbers. This is off by default; you can turn it on in Settings.")
        case .bodyClock: Explanation(id: id, title: "Your body clock",
            meaning: "Whether your body naturally prefers earlier or later sleep and wake times. It's partly genetic and tends to run latest around age 20.",
            forYou: "Being an evening type isn't laziness. Your peak focus comes later in the day, so morning classes need more help: morning light, a steady wake time and a smaller weekend shift.",
            howWeGotIt: "We use the method of the Munich ChronoType Questionnaire (Roenneberg), applied to your tracked sleep: the midpoint of your sleep on free days (weekend mornings), corrected for catch-up sleep.")
        case .socialJetlag: Explanation(id: id, title: "Social jet lag",
            meaning: "The gap between when your body wants to sleep (on free days) and when your schedule makes you sleep (on school days).",
            forYou: "Under an hour is the goal. Cutting your weekend shift is the easiest way to shrink it.")
        case .caffeineCutoff: Explanation(id: id, title: "Caffeine cutoff",
            meaning: "The latest time to have caffeine so that very little is left in your body at bedtime.",
            forYou: "Caffeine takes about 5 hours for half of it to leave your body, and about twice that on the combined pill, ring or patch (the app uses the longer time if you use one). So an afternoon coffee is still partly there at midnight, even if you can fall asleep. It makes sleep lighter.",
            howWeGotIt: "The latest time a 12 oz drip coffee (140 mg) would be down to under 25 mg by your planned bedtime, rounded down to the half hour. A smaller drink, like a single espresso, can be a little later and a bigger one needs to be earlier; the Caffeine screen tells you when what you've had adds up to too much. On the longer half-life that time can come before you're even up. Then the cutoff shows as \u{201C}None today\u{201D}, and the app tells you the biggest single drink you could have soon after waking instead.")
        case .caffeineLeft: Explanation(id: id, title: "Caffeine left at bedtime",
            meaning: "How much of today's caffeine is predicted to still be in your body when you go to bed.",
            forYou: "Under 25 mg is the goal. That's about a fifth of a 12 oz drip coffee.",
            howWeGotIt: "Why 25 mg: in sleep-lab studies, caffeine still in the body at bedtime made sleep lighter and shorter even when people fell asleep fine, and bigger amounts did more. There's no exact safe line, and some people are more sensitive than others. 25 mg is a cautious rule of thumb the app uses, a small amount where the effect is usually minor, not a medical cutoff. The caffeine cutoff test can show what works for you.")
        case .coffeeNap: Explanation(id: id, title: "Coffee nap",
            meaning: "Drinking a small coffee and then napping for 20 minutes. The caffeine kicks in just as you wake up.",
            forYou: "Only worth it when your afternoon dip starts before your caffeine cutoff.")
        case .cutoffTest: Explanation(id: id, title: "Caffeine cutoff test",
            meaning: "A personal experiment: for 21 days the app compares your sleep on days your last caffeine was early with days it was late. A day with no caffeine counts only if you logged something else that day, so a day you forgot to log isn't counted as caffeine-free.",
            forYou: "It tells you your own cutoff instead of a general rule.")
        case .period: Explanation(id: id, title: "Period",
            meaning: "The days you bleed, the start of a new cycle.",
            forYou: "You may sleep a little more; cramps can break up sleep on the first days.")
        case .follicular: Explanation(id: id, title: "Follicular phase",
            meaning: "Starts on the first day of your period and runs until ovulation. Estrogen rises through it. The app shows your bleeding days separately as \u{201C}Period\u{201D}, so \u{201C}Follicular\u{201D} here means the days after it.",
            forYou: "Some women feel their best this week; many notice no difference. Train as planned and go by how you feel.")
        case .ovulation: Explanation(id: id, title: "Mid-cycle (estimate)",
            meaning: "Ovulation is when an egg is released, usually about 12 to 14 days before your next period, though it varies more than that. The app's mid-cycle days are a rough estimate from your cycle length; it can't tell when you ovulate.",
            forYou: "This is not your fertile window. Don't use it to avoid pregnancy. If you're on a method that stops ovulation, this doesn't apply to you.")
        case .luteal: Explanation(id: id, title: "Luteal phase",
            meaning: "From ovulation to your next period. Progesterone rises, which raises your temperature and resting heart rate a little.",
            forYou: "A slightly higher heart rate and lower HRV are normal here, and some people sleep more lightly. Many women notice no difference in how they feel. In the last 7 days before your period the app adds a little to tonight's sleep need. Your recovery score isn't adjusted, so a slightly lower score now is expected. The sick check allows for it too.")
        case .pillPack: Explanation(id: id, title: "Pill pack",
            meaning: "On the combined pill, ring or patch you take hormones for a set number of days, then usually have a short break: 21 days and 7 off, or 24 and 4 off for some pills. Some people skip the break and use it continuously.",
            forYou: "These methods stop ovulation, so cycle phases like ovulation and luteal don't apply to you. The app doesn't predict them. Set your pack type and today's pill in Settings or on the Cycle screen so the break lands on the right days. You can also skip a break there.")
        case .withdrawalBleed: Explanation(id: id, title: "Withdrawal bleed",
            meaning: "The bleed in your break week. It's caused by the drop in hormones from the pill, ring or patch, not a true period.",
            forYou: "It doesn't mean you ovulated, and it's fine if it's light or doesn't come. Missed or late with a pill, ring or patch and no bleed in the break? Start your next pack, ring or patch on time anyway. Take a pregnancy test now, and again in 3 weeks if you had sex in the last 3 weeks. Sex in the last 5 days? Ask a pharmacist about emergency contraception.")
        case .timeChange: Explanation(id: id, title: "Clock change",
            meaning: "When the clocks change by an hour, your body clock doesn't change overnight. It takes a few days to adjust.",
            forYou: "You can keep your usual bedtime and wake time by the clock (nothing moves; when the clocks go back you just get an extra hour that night), or use the extra hour to become a slightly earlier riser. Neither option changes your alarm.")
        case .alcohol: Explanation(id: id, title: "Drinks and your body",
            meaning: "Alcohol can help you fall asleep but makes the second half of the night lighter, with less REM and more wake-ups, and raises your heart rate overnight.",
            forYou: "The app compares your own nights with and without drinks so you can see the effect on you.")
        case .lateNight: Explanation(id: id, title: "Late-night cost",
            meaning: "What a bedtime well past your usual does to the next day and the day after, from your own nights.",
            forYou: "One very late night can take a couple of days to fully recover from.")
        }
    }
}
