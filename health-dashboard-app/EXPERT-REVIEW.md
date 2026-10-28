# Expert review (Oct 28, 2026)

Two BMad parties reviewed every calculation, health message and screen of the app:

- **Women's health experts** (`womens-health-experts`): an adolescent gynecologist, a sex-differences physiologist, a sleep scientist, a sports-medicine doctor for female athletes, an eating-disorder dietitian, a women's-health pharmacist, a college psychiatrist, a student-health physician and a women's-health epidemiologist. Brief: every number and message accurate for women and based on women's data, plus what would help college women.
- **Design review** (`design-review`): a design director, a typographer, a colour and data-vis designer, a layout designer, a motion designer, a UX researcher, an accessibility lead, a Watch and widget designer and a content designer. Brief: a flawless, beautiful, fluid app.

Personas live in `_bmad/custom/bmad-party-mode.toml`. This file lists what changed and what's left as a recommendation.

## Health: fixed in the app

**Built on women's data now**
- Fitness age uses the FRIEND 2015 women's VO₂ max medians (the norm Apple uses), shown as a range because the Watch's estimate can be off by several points. Under-20s are compared with women in their 20s. No male norms anywhere.
- Ovulation is estimated at cycle length − 13 (women average a 12.4-day luteal phase, not 14) and shown as "Mid-cycle (estimate)", with "not your fertile days; don't use it to avoid pregnancy".
- Recovery, stress and the sick check allow for the cycle on natural cycles (luteal: resting HR about +1.5 bpm, HRV about −4%; period days the reverse), and not on the pill, ring, patch, implant or shot, where heart rate and temperature don't swing with the pack.
- Stress compares her heart rate with her own still hours, is shown as bands (not a 0–100 score), says "body signals, not how you feel", and lists other causes (caffeine, medicines, heat, a meal, getting sick, her cycle).
- Sick-check cutoffs scale with her own day-to-day spread; logged fever, sore throat or cough override "No signs".
- Hard-training and active-hour thresholds scale with her body weight (about 8 and 1 kcal/kg) instead of figures sized for heavier bodies.
- Caffeine on estrogen-containing birth control: half-life about 8 h ("about one and a half times as long"), not 9 h. Up to 400 mg a day is generally fine; under 200 mg if she could be pregnant or is trying; one drink over 200 mg is "a big single dose".
- Alcohol: a US standard drink takes most women about 2 hours to clear; women reach a higher blood alcohol from the same drinks; at 4+ drinks in an evening a calm alcohol-poisoning safety note.
- Water: women's guidance (about 9 cups, 74 oz, a day from drinks; more if pregnant or breastfeeding); default goal 72 oz for new installs; never "catch up" faster than about 1 L an hour.
- Calorie estimates are "often off by 20–30% or more"; Sex must be set to Female in Apple Health for the resting estimate.

**Safety added**
- Pill: no-bleed advice now says start the next pack on time plus a pregnancy test; CDC 2024 missed-pill, ring and patch rules; mini-pill 3-hour window; a late pack-start warning; "Medicines and your pill" (rifampin, some seizure medicines, St John's wort, modafinil, tirzepatide…; most antibiotics are fine); being sick on the pill.
- Cycle: 90 days without a period → see a clinician; RED-S (under-fuelling) wording, including that a pill bleed can't show it; cycles over 35 or under 21 days, or very variable, are "worth mentioning to a clinician"; one ACOG heavy-bleeding definition with an urgent tier; bleeding red flags on IUD, implant and shot; full ACHES warning signs; migraine with aura on estrogen; PCOS diagnosis notes for young women; pregnancy-test timing.
- Sick check: three tiers of when to get care (call 911 / today / book a visit); "Fever or trouble breathing? Get checked." on Today and in the alert.
- Mental health: the 988 row shows to anyone who logs stress 5, or 4–5 on 3 of 5 days (not only with PMDD); PMDD line in the late-luteal "why off" reason; mood notices for hormonal methods; exam-week overwhelm card; ED support line (ANAD 1-888-375-7767) and campus counseling.
- Sleep and exams: never plan less sleep than she needs to land on a sleep cycle; drowsy-driving warning after all-nighters; sick-before-an-exam card; insomnia / CBT-I card.
- Onboarding: "Not a medical device. In an emergency call 911."

## Health: recommendations not built yet

Features (biggest value first):
1. **Missed-pill helper** that walks through what to do for her method today, with emergency-contraception options (levonorgestrel over the counter; ulipristal by prescription, up to 5 days; the copper IUD).
2. **Daily pill reminder** on the iPhone and Watch (typical-use pill failure is about 7% vs under 1% with perfect use), with a 3-hour alert for the mini pill.
3. **Daily mood rating** (mood, anxiety, irritability, 1–5) and a cycle-aligned chart she can show a doctor; the standard way to confirm PMDD.
4. **Doctor-ready export**: cycle lengths, flow, symptoms, mood.
5. **Athlete setting with RED-S screening**: missing periods, long cycles, falling HRV with rising resting HR over weeks of hard training; bone-health card; "eat within a couple of hours after training".
6. **Iron prompt**: heavy periods plus tiredness, or resting HR creeping up → "ask for a ferritin test" (about 40% of US females aged 12–21 are iron deficient, most without anemia).
7. **Personal cycle baselines** after 2–3 cycles: compare each day with the same phase of her own past cycles; a "your cycle pattern" chart; detect ovulation from her wrist-temperature rise (natural cycles).
8. **More symptom choices**: body aches, chills, vomiting or diarrhea (opens the pill card), burning when you pee (UTI), bleeding after sex, between periods, pain with sex, unusual discharge, period pain that ibuprofen doesn't help or that keeps her from class.
9. **Campus resources** in Settings: her counseling center and student health numbers next to 988.
10. Conditions "Anxiety or depression" and "ADHD medication" (stimulants raise resting heart rate).
11. Face ID lock for cycle, mood and conditions.
12. Let the caffeine cutoff test set her own caffeine half-life.
13. Alcohol logged as standard drinks, with the sleep comparison split by amount.
14. "Can I go to class?" (24 hours fever-free without fever reducers and improving), a yearly vaccine reminder (flu, COVID, MenB, HPV through 26), a yearly chlamydia/gonorrhea screening note for sexually active women under 25.
15. "Show agreement" (e.g. "your energy score matched your check-ins on 18 of 25 days") and an option to hide scores during exams (sleep anxiety).

## Things worth knowing (content ideas for the app)
- The pill's break-week bleed is a withdrawal bleed, not a period, and it can hide a missing period from under-fuelling.
- Caffeine lasts about one and a half times as long on estrogen-containing birth control; coffee or tea with meals cuts iron absorption.
- A standard drink takes most women about 2 hours to clear, and nothing speeds it up.
- Women's resting heart rate and temperature rise a little after ovulation; HRV dips. That's normal.
- Three months without a period, cycles over 35 days, soaking a pad or tampon every hour, or period pain that stops you going to class are all worth seeing someone about.
- PMDD is a real, treatable condition, not "just PMS".
- Mood can shift in the first months on a new hormonal method; tell your prescriber.
- Most antibiotics don't affect the pill; rifampin and some seizure medicines do.
- Iron: 18 mg a day for women 19–50; low iron is common and causes tiredness.

## Design: fixed
**System** (used by every screen)
- One palette with one hue per feature, end to end (tile → screen → Watch): HRV and recovery indigo, sleep purple (moved away from indigo), energy mint, caffeine yellow, water blue, stress orange, cycle and period pink. Coral only means "worse" (and Awake). Light-mode chart colours reach 3:1 on white; text on tints 4.5:1.
- A type scale of 14 roles (was 27 sizes), numbers in rounded bold with fixed-width digits so they don't jiggle, titles capped so the largest text size keeps its hierarchy.
- Spacing and corner-radius tokens (cards 16pt padding, 24pt corners; 12pt between cards); rings draw inside their frames.
- A motion system (press, log, fill, select, reveal, data swap, page, commit, undo) that falls back to fades with Reduce Motion; numbers animate; logging gives haptics and a 5-second Undo toast.
- Charts: readouts keep a steady height while you drag, show a summary at rest, clear with a tap, tick a haptic per point, and VoiceOver can step through them; every chart has an audio-graph description.

**Screens**
- The same header on all four tabs (date, title, Settings avatar). Today has one hero (recovery), one bedtime ("Bed by … · Up at …" and one plain sentence) and an alarm chip that really switches the alarm. Body is grouped into Rhythms, Vitals and Progress with nothing repeated from Today. Settings is regrouped, with a Widgets & Watch how-to.
- Log only logs: one-tap period flow chips, four equal time chips (Now / 30m / 1h / 2h), History links, Undo after every log. Onboarding is three steps; notification permission is asked when it's needed.
- Detail screens: one title each; honest HRV and resting-heart-rate charts (her usual range as a band, a y-range that doesn't turn a 3 ms wobble into spikes); sleep stages compared with her own usual; explanations restructured as "What it is / What to do / How it's worked out" and shortened.
- Words: one name per thing (Alcohol, Weekend shift, Streaks, Your week, Sick check, Example data, focus peak, "your usual"), times as "8:15am", ranges "8:00–8:25am", the logged confirmation echoes the time she picked.
- Accessibility: no sideways scrolling or mid-word breaks at the largest text size; section headings are headings; 44pt targets on text links; VoiceOver labels say "About …" and read symbols as words.
- Watch: titles in the clock row; logging without scrolling, with Undo on the tile; Tonight leads with "Bed by"; a "now" point on the Energy curve; a water tile; text follows her text size; "no numbers for today yet" after the 4am rollover instead of yesterday's; opens on the page that fits the time of day.
- Widgets and complications: tinted and accented rendering, empty states sized for each family, stale numbers greyed with the day shown, the latte button shows when it's past the cutoff, and the bedtime complication rises in the Smart Stack before bed and says whether the alarm is armed.

## Design: recommendations not built yet
- Show the Energy curve inline on Body (today it's a tile that opens it) and an Energy complication / Smart Stack widget with a "now" dot.
- A "Staying up late?" row and the clock-change line on the Tonight card in the week before a change.
- Bedtime reminders as a general setting (today they live in the clock-change plan).
- A one-time Today card on day 3 that introduces widgets, the Watch and health conditions.
- Alcohol has no colour of its own (it shares purple with sleep); a ninth hue would need care to stay distinct.
- A snooze on the Watch alarm was left out on purpose: the smart-alarm session can't outlast its window, and the iPhone backup alarm covers that case.
