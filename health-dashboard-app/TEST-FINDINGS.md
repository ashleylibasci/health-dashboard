# Test round 1: findings

Six college-student testers walked through the code for each flow (no device available in the cloud session). Each item has an ID, severity, where, and the fix. Testers: Maya (combined pill, pre-nursing), Jordan (night owl, CS), Priya (D1 runner, Watch), Theo (first-time user, large text), Sam (stats, the math), Riley (PCOS/irregular, design).

Status column is filled in as fixes land.

## Blockers

| ID | Problem | Where | Fix |
|---|---|---|---|
| B1 | Bedtime is fixed at 12:30am and can't be changed anywhere; "up by" only offers 7:30–9:00. Drives cutoff, wake plan, smart alarm, streaks, water pace, "Bed by". | DataStore.swift `bedtime`; WakePlanView.swift:14 | Bedtime + up-by settings at any time (onboarding + Settings + Wake plan). |
| B2 | Sample data shown as yours with no label on Today/Sleep/Body/Energy/Watch for days 1–13; no "night N of 14" progress. | AppModel.swift init/refresh `loadSample()` | "Example data · night N of 14" banner on every tab and Watch; use real last night as soon as it exists. |
| B3 | Real-data refresh keeps sample values when something is missing: HRV/RHR (no reading yet today), cycle day 22 (no period logged), chronotype nights. | AppModel.swift:213-224 | Fall back to the latest real reading or "no data", never the sample. `cycleDay = nil` when no period. |
| B4 | Text ignores Dynamic Type (all fixed sizes); fixed row heights would clip. | ~845 `.font(.system(size:))` | Scaled fonts app-wide; min heights instead of fixed heights. |
| B5 | Data loads once per launch: a suspended app shows yesterday's numbers next morning; Watch never re-synced. | HealthDashboardApp.swift `.task` | Refresh + push to Watch when the app comes to the foreground; Watch shows "as of" and greys stale data. |

## Wrong

| ID | Problem | Where | Fix |
|---|---|---|---|
| W1 | Midnight rollover: after 12am the evening's caffeine vanishes, a latte at 12:15am reads "~5 mg at bedtime", energy bank > 100%, "next up: grogginess", greeting "Good morning" at 1am, water/mood reset. | AppModel `now`, `todaysDrinks`, Energy.swift bank | App day rolls over at 4am; minutes after midnight count as 24:xx until then; clamp bank to 0–100. |
| W2 | Pill pack day anchored to bleed start (bleed is in the placebo week), so the pack is ~5 days off; breakthrough spotting resets it. | BodySignals.swift:60 | "First pill of this pack" date setting; fallback treats bleed start as ~pack day 24. |
| W3 | Day past cycle length: "Period expected today" every day, late-luteal forever, calendar wraps and contradicts the hero. | AppModel+BodyLog.swift; Planning.swift; CycleView | Overdue state ("Day 35 · longer than your average"), no luteal adjustments, no wrap. |
| W4 | PCOS + pill shows the irregular view, the pack disappears. | BodySignals.swift:58 | Birth control method wins; PCOS notes still shown. |
| W5 | Conditions promise features that don't exist (PMDD "crisis line always visible", endometriosis export, migraine log…). | BodyLogShared.swift:119-129 | Describe only what each condition does; build the PMDD crisis line (988). |
| W6 | Dead toggles/buttons: sick alerts, peak/dip nudges, friend streaks, reaction test, Settings name, smart alarm defaults on, exam chip shows fake exams. | various | Build peak/dip nudges + sick alerts as local notifications, remove friend streaks and the reaction test, fix name, alarm off by default, exams only when added (with an editor). |
| W7 | Sleep debt overweights last night (~2.1×) and scales up with few nights. | SleepNeed.swift:163-175 | Plain sum of shortfalls over the last 14 nights (recency-weighted, weights sum to the real night count). |
| W8 | Energy score rises the later you wake; zones named "Morning peak" at 5pm; "What moved today" lists drivers the model doesn't use. | Energy.swift:379; AppModel+EnergyPlanning | Score over a fixed 16h day from wake; neutral zone names after late wakes; drivers computed from the model. |
| W9 | "Usual" is hard-coded (recovery 78, energy 74). | AppModel.swift:92; EnergyView:20 | Personal average from history, fallback labelled "typical". |
| W10 | Stress average counts sleeping hours as calm; workouts without steps (swim, bike, lift) count as stress; "vs your usual" claim with fixed bands; three label sets. | BodySignals.swift:105; AppModel.swift:231 | Exclude sleep hours and workout/high-active-energy hours; one label set; drop "vs usual" wording or compute it. |
| W11 | A hard training day triggers "You might be getting sick"; luteal phase only relaxes wrist temp; confidence labels read like data quality. | BodySignals.swift:149-171 | Training-day context, luteal RHR/HRV allowance, labels "Unlikely / Possible / Likely". |
| W12 | Fitness age clamped at 15, "for your age group" ignores age, card contradicts itself. | BodySignals.swift:183; FitnessView:45 | "Under 20" display, age-aware bands when age is known, consistent copy. |
| W13 | Caffeine: half-life ignores combined pill/ring/patch (~doubles); cutoff assumes a 100 mg drink; "best window" inverted for late wakers; logging before midnight lands in yesterday and disappears from the list; edit sheet can push a time 23h into the future. | Caffeine.swift; CaffeineView; LogView | Method-aware half-life, dose-aware warning, clamp window, 4am app day, edits keep the right day. |
| W14 | Watch drinks get the phone's receive time, duplicate Health samples, can't be undone, silent save failures. | AppModel.handle; Watch LogPage | Carry tap time + id; the phone writes Health; undo on the Watch. |
| W15 | Water/caffeine edits and deletes never reach Apple Health; logs during the first 14 days never written. | AppModel.swift:257-307 | Write with ids, update/delete by id, write during sample period too. |
| W16 | DST morning (Sun Nov 1): elapsed-minute math puts the alarm window and recorded wake an hour off. | Time.swift `minutes()`/`date()` | Wall-clock DateComponents math. |
| W17 | Week recap never fills on a real phone. | AppModel.swift:245 | Build last week from real nights, check-ins, caffeine. |
| W18 | Naps ≥ 2h replace "last night"; a 1h+ wake splits a night; "last night" can be days old. | HealthKitService.swift:43-75; AppModel:205 | Merge gaps < 2h, main sleep = longest session ending in the last 18h, otherwise "no sleep recorded last night". |
| W19 | Habit comparisons (late nights, drinks, cutoff test) conclude from 3 nights; late = absolute 2am; drinks after midnight count for two nights; free-night rebound can never fire. | BodySignals.swift; AppModel+Signals | 5+5 nights minimum with n shown; late relative to her median; evening = 5pm–5am; rebound needs 2+ free nights. |
| W20 | Health period import starts a new period mid-bleed after 10 days. | HealthKitService.swift:124 | New period after 2+ bleed-free days. |
| W21 | Custom alarm windows (exam mode) get overwritten by the next push; re-sent window can cancel a good Watch alarm; the alarm repeats on weekends. | AppModel.pushToWatch; SmartAlarm.swift | Persist the override with its date; don't cancel until the new schedule is accepted; weekend/free-day toggle. |
| W22 | "Your alarm lands N min into a cycle" uses a made-up 7:45 alarm. | AppModel.swift:89 | Only when she's set an alarm time in the app. |
| W23 | ED history only hides calories; steps/effort/exercise prescriptions still shown. | EnergyView, BodyView, Settings | Hide them all and explain disabled toggles. |
| W24 | Explanations/copy that don't match the app: luteal "adjusts recovery", onboarding "learns from temperature", Sick "already adjusted temperature and resting HR", time-change "shifts gradually", melatonin timing, follicular definition, break week with no pregnancy caveat. | Explanations.swift and inline | Rewrite to match. |
| W25 | Days-since-period off by one across screens; streaks ignore missed days and check-in streak reads 0 before today's check-in. | CycleView, LogView, BodyView; AppModel+Signals | One definition; calendar-aware streaks. |

## Confusing and polish (selected)

- C1 Two different "Energy" numbers (bank % on Body/Watch, score on Energy screen). Name them "Energy left" and "Energy score".
- C2 Today water tile says "ml bottles", rounds differently from Water screen; bottle plurals; "1.5 to 2 litres" copy; y-axis without "oz"; custom amount field may log the previous value.
- C3 Wrist temp shown without a unit (°C vs °F).
- C4 Sick screen "I feel fine" clears cycle headaches (shared symptom log); "Fatigue" vs "Tired".
- C5 Cycle colors: follicular/ovulation fail 3:1 on white; period vs follicular hard to tell with colour blindness; luteal text contrast 4.3:1.
- C6 Watch energy chart blocks page swipes; selection never clears.
- C7 Jargon without ⓘ on Today (HRV, Resting HR, Stress, Regularity); "Learn how we got this number" far from its number; links that open the wrong place.
- C8 Charts without VoiceOver summaries.
- C9 Onboarding: no sleep-setup help, step counter repeats, Natural preselected, copper IUD under "hormonal".
- C10 Drinks: "2 shot", unit doesn't update in editor, future dates allowed, double-tap logs twice; sample analysis shown without "Example" tag.
- C11 Log tab shows "Ovulation" to a mini-pill user; mini pill still paints future period days; hormonal IUD gets countdowns.
- C12 Delete-all doesn't say it restarts setup; JSON export isn't doctor-ready.
- C13 Smart alarm rings ~25 min into a 33-min window though copy says "latest".

---

# Round 1 status
Fixed in the first fix round, then re-checked by the same testers in round 2. Each tester's re-check table: most items **Fixed**; the remaining "partly" items became round-2 findings below.

# Round 2: re-test + new findings (all addressed in fix round 2)

Each tester re-checked their round-1 list, then hunted for regressions. Full notes: the round-2 sections below are the condensed version.

| Area | What round 2 found | Fix |
|---|---|---|
| Day boundary | Fixed 4am rollover broke bedtimes after 4am; last night's wake on the wrong axis; calendar vs app day mixed (steps, cycle, exams, check-ins) | Rollover = later of 4am and bedtime + 2h (cap noon); one day definition per feature; `AppDay.pastTime` picks the most recent past time |
| Caffeine on the pill | 9h half-life gave a 6:00am cutoff, past-time "latest" suggestions, "woke late" note | `caffeineCutoffShown` nil when before wake → "one small drink early" copy with mg left at bedtime |
| Pack | Sample cycle day created a fake pill number; method switch kept 24+4; no rollover/drift check | Only `packDay` decides; `setPackType`; "Did you start your new pack?" card, skip-a-break, bleed-outside-break check |
| Cycle | Long cycles (>45 days) fell back to "usual ~29"; "Period expected today" for 3 days; overdue for IUD/mini pill; "late" wording | `cycleLengthsRunLong` → irregular view with reason; "Due around now" once; method-specific copy |
| Watch | `syncedAt: now` on stale data; Watch showed recovery when phone had none; no cold-launch snapshot; Watch alarm left on at weekends; sick alert invisible in foreground; nudges only on open days | `lastRefreshed` stamp; optional recovery; snapshot request on launch/activation; evening "open your Watch app" reminder; notification delegate; tomorrow's nudges |
| Math | Last night counted twice in energy; rebound biased high; "late nights" = weekends; absolute 600 kcal training; partial-day HRV; recap habits circular; weak confidence gate | Debt from prior nights; rebound weight scaled; within-weekday comparison; relative training; overnight HRV; recap labelled as estimated, habits from check-ins; stricter gate, median baselines |
| First run / large text | Accuracy tips thought Health wasn't connected; hybrid real/example screens; clipping in rings, gauges, chips, dial, legends, fixed-width fields; text-size change reset the app | `healthConnection`, real nights in history, "N of 14"; scaled/stacking layouts; no forced rebuild |
| Tone & colour | 988 buttons low contrast; drinks tiles judged by colour; future pills faint; 8pt phase letters | Filled 988 buttons; words not colours; stronger borders; 11pt letters + strip labels |

## Still open (known, not bugs)
- Pill "Taken" logging and pill reminders (in the design, not built; nothing claims them).
- Doctor-ready export (current export is raw JSON).
- Friend streaks (removed).
- Everything was verified by reading code and type-checking against stand-in SwiftUI modules, plus 69 HealthCore unit tests. Nothing has run on a device or simulator yet. **The Watch files were syntax-checked and read line by line but not type-checked.** First job on a Mac: build both targets and fix anything the real SDK flags.

---

# Round 3: the real app in the simulator (Oct 27, 2026)

The first round on running code. The six testers are the "student-testers" BMad party (`_bmad/custom/bmad-party-mode.toml`): **Maya** (combined pill 21+7), **Jordan** (night owl, hormonal IUD, periods mostly stopped), **Priya** (D1 runner, natural cycle, Apple Watch, thinks in oz), **Tessa** (first-time user, largest text size, VoiceOver), **Sam** (stats, copper IUD), and **Riley** (PCOS, 35–60 day cycles, PMDD and eating-disorder history on, light mode). Each one tested her own setup through `-demoCycle`, from screenshots and element trees captured by `HealthDashboardUITests/TestRound.swift`. The Watch pages were captured from the paired Watch simulator. The real build (Xcode 27.1 SDK) had one error (SickView) and one warning (orientations); both are fixed.

Limits: the simulator clock can't move, so after-midnight, the 4am rollover and the Nov 1 clock change are untested. There are no real workouts and the smart alarm hasn't rung. Maya's "pack day lost" (M2) was the harness: every run starts with `-resetData`.

Duplicates are merged; the IDs in brackets are the testers' own.

## Wrong numbers and contradictions
| ID | Problem | Seen by | Status |
|---|---|---|---|
| N1 | One night shows three sleep totals. "7h 35m asleep" includes 14 min awake, the stage tiles add up to 7h 21m, and fell asleep 12:42am → woke 7:21am is 6h 39m. The chart's VoiceOver summary is from a different night. | Sam S1, Maya M4 | Fixed |
| N2 | HRV and resting HR each show two values with opposite verdicts for the same night. The hero says "43 ms, 6% below usual"; the chart card says "46 ms, right around your usual 46 ms". Resting HR is 70 vs 68. | Sam S2, Maya M5, Jordan J10, Priya P2, Riley R4 | Fixed (the -demoSick example still shows a chart from ordinary nights) |
| N3 | Five different "tonight" plans: Today "bed 12:30, up 8:22, 7.9h"; Sleep "tonight 8h 24m"; sick check "aim for 8h 54m"; Why off "bed by 12:00am"; Watch "7h 55m". Wake times 8:22, 8:25 and 8:30 aren't explained. Today's plan is shorter than the need and doesn't say so. | Sam S3, Jordan J9, Priya P3, Maya M15 | Fixed: each wake time named; 11:05pm explained as whole sleep cycles; Settings counts time asleep like Today |
| N4 | The same recovery of 69 is "Take it steady" on Today and the Watch but "Go easy" on Energy. | Priya P4 | Fixed |
| N5 | Body clock shows the free-day sleep midpoint as both 5:21am and 5:50am, unlabelled. | Sam S8, Maya M7, Jordan J11 | Fixed |
| N6 | Example data feeds claims about her: "7 of 7 with a recorded night" under "no nights yet", "best days had in common" from 3 days, badges "3 of 9 earned", "Caffeine scientist 14/21", "cutoff test 14 of 21 nights", "In bed on time 2 nights in a row". | Sam S5, S6, Tessa T5 | Fixed: example reasons and recap say so; no pattern from one night |
| N7 | The "7 nights on time" badge shows 5/7 ("in a row") while the current streak is 2. | Sam S6, Maya M12 | Fixed |
| N8 | "VO₂ max 38.2 · Below average for a 20-year-old" with age not set. | Sam S7, Maya M6, Priya P12, Riley R3 | Fixed |
| N9 | The cycle view invents a period: with no period logged it fell back to the example cycle ("day 22 of ~29", P days on Oct 6–10, "Late luteal… before your period", a luteal allowance in the sick check, "Day 22 · Luteal" on Log). This affected a hormonal-IUD user with spotting only and a first-time natural user. It's a regression of round-1 B3. | Jordan J1, J2, J7, J8, Tessa T4 | Fixed: no cycle day without a logged period |
| N10 | Period length is fixed at 5 days: a logged day 6 shows as Follicular, and the prediction is a day short. | Sam S4 | Fixed: the predicted period is as long as hers |
| N11 | Body tile "Day 53" vs Cycle and Log "52 days since". | Riley R5 | Fixed: the chart's "so far" matches the hero |
| N12 | Watch Energy page: "22% Second wind" puts energy left next to an energy-score zone name. | Priya P5 | Fixed |
| N13 | Watch Log: "0 mg today" plus a red "Past your cutoff. It may cost you sleep." | Priya P9, Sam S9 | Fixed |
| N14 | "Typical 74" / "a typical 78" with no source. The stress band is called "Usual" with no personal baseline. | Sam S11, S12, Tessa T16 | Fixed: "starting point" everywhere, and the ⓘ says where 78 and 74 come from |
| N15 | "Paying back 15–30 minutes a night for a week clears most of it" (it clears 35–70% of 5h). | Maya M8 | Fixed |
| N16 | Too much precision: deep sleep "+2m vs usual", "aim for 8h 54m". | Sam S10 | Partly: one-night stage differences still to the minute |

## Women's health and tone
| ID | Problem | Seen by | Status |
|---|---|---|---|
| H1 | Settings → Your pack shows "Skip this break" with no pregnancy caveat (the Cycle screen has one) and no "one-phase packs only" note. | Maya M1 | Fixed |
| H2 | No-period methods still get period wording and nags: "This eases once your period starts", "period on 0 days in 2 months", a "Full cycle tracked 0/2" badge, a "NEXT PERIOD" header, "hormonal iud". | Jordan J3, J4, J5, J14, J15, Maya M14 | Fixed; a hormonal IUD or mini pill with no period logged now gets its method's view, not "log your next period" |
| H3 | Settings ("most still ovulate, so the app shows phases") and Accuracy tips ("most hormonal methods stop ovulation") disagree for the hormonal IUD. | Jordan J6 | Fixed |
| H4 | The sick check fired ("Sick check: likely · 4 signals"), but Today has no sick card and "Why do I feel off?" says "Most likely: sleep debt". | Priya P1 | Fixed |
| H5 | The irregular view's "Your last 2 cycles" chart draws no bars (the data is in the element tree: 58 and 47 days). | Riley R1 | Fixed |
| H6 | With eating-disorder history on, Fitness still shows "below average", "your peak was 41.0", "Down 2.8", and Water says "1.9 bottles behind a steady pace". | Riley R3, R9 | Fixed: fitness age, the history line, the age prompt and the water pace line are hidden too |
| H7 | PMDD is on, but the stress check-in (where she picks 5, "very stressed") has no 988 row. | Riley R8 | Not seen on screen (the 988 row shows at level 4 or 5 with PMDD on) |
| H8 | Pill 25 is "break" on 21+7 but "placebo" on 24+4. | Maya M3 | Fixed |
| H9 | Melatonin window 11:37pm–12:37am sits at sleep onset (melatonin starts ~2h before). "Afternoon dip… not lunch" overstates. | Maya M11 | Partly: the Energy copy is right; Body clock still shows an 11:37pm–12:37am melatonin window |
| H10 | The caffeine cutoff copy is hard to parse ("No time left today when your Latte clears enough…", "Cutoff: Early only"). "Regular coffee 95 mg" vs a "Drip coffee 140 mg" chip. The 25 mg bedtime goal has no source. | Maya M9, M10 | Fixed: the cutoff is for the 12 oz drip coffee (140 mg) the copy names |
| H11 | Clock-change copy: "For an evening type, falling back is a free hour earlier" reads backwards. | Jordan J13 | Fixed |

## Large text (AX5) and VoiceOver
| ID | Problem | Seen by | Status |
|---|---|---|---|
| A1 | Label-beside-value rows don't stack, so words break into letters: "Be / dti / me" (bedtime, onboarding and Settings), "Tak / e it / ste / ad / y" (Recovery card), "Wh / en / did / yo / u…" (Log), "Sk / ip" / "N / ot / se / t" (Age), "Ex / ac / t / si / ze". | Tessa T1, T3, T7, T8, T22 | Fixed (the quick-log drink card stacks too; not re-shot at AX5) |
| A2 | Settings › Cycle: the picker value is drawn one letter per line and overlaps Health conditions, Redo setup and Water. | Tessa T2 | Partly: no overlap, but "Natural cycle" is clipped |
| A3 | Two-column Body tiles truncate every title ("Rest…", "Bre…") and the HRV pill reads "H / R / V / 6 / 4 / % / 3". | Tessa T10, Priya P11 | Fixed |
| A4 | Times and numbers break across lines ("8:2 / 5", "5: / 21 / am", "38 / .2"), as do phase names and "Endometriosi / s". | Tessa T11 | Partly: the alarm time keeps together; the sleep-stage axis and long phase names still wrap |
| A5 | Chart axis labels overprint ("2pmbed12:30", "9a12p3p6p9pm"); the stress legend breaks into letters. | Tessa T12, T13 | Partly: the sleep-stage axis |
| A6 | Segmented controls stay ~11 pt and 32 pt tall. "Female" is preselected on an "all optional" step. | Tessa T9 | Partly: nothing preselected; the water steppers are still small |
| A7 | At AX5 the example-data banner fills the first screen of every tab and sub-screen. | Tessa T6 | Fixed |
| A8 | The log-time chips scroll sideways and hide "1 hr ago" and "2 hr ago". | Tessa T7 | Fixed (the common-drink chips wrap too) |
| A9 | VoiceOver: the banner icon reads "Search Document"; "First,, about you"; "What is How stressed do you feel??"; chart audio graphs read minutes-of-day and ml; the inner time pickers are just "Time Picker". | Tessa T18–T21 | Fixed: charts read as one element with a summary |
| A10 | "Streaks and wins" title has no left gutter; "Step 3 / of 5" and a lone "?" wrap. | Tessa T14, T23 | Fixed |

## Units, colour and polish
| ID | Problem | Seen by | Status |
|---|---|---|---|
| U1 | The default bottle is 16.9 oz (500 ml) and the goal is "3.8 bottles". The 64 oz goal never rises on training days. | Priya P6, P7, Tessa T17 | Partly: 24 oz bottle and quarter bottles; the goal doesn't rise on training days |
| U2 | Wrist temperature is in °C only. | Priya P8 | Fixed |
| U3 | Stress "Raised" and "High" have the same brightness (hue-only), and the bars are under 3:1 on white. Locked badges are about 3:1. | Riley R2, R6 | Fixed; Raised hours also get a ● |
| U4 | The caffeine timing strip relies on colour alone (green next to salmon); "Show as one line" on the 988 card isn't styled as a control. | Riley R10, R7 | Fixed |
| U5 | Onboarding step total changes mid-flow ("Step 2 of 5" → "Step 3 of 6"). | Maya M13 | Fixed |
| U6 | No am/pm on "Bed by 12:30, up 8:22". | Jordan J12 | Fixed (the weekend shift too) |
| U7 | The energy curve's range is tiny (53–59), so scrubbing reads flat. | Priya P13 | Partly: the readout helps, but the curve is still flat |
| U8 | Welcome screen jargon (HRV, VO₂ max) has no plain gloss. | Tessa T15 | Fixed |

## Round 3 re-check (same evening, after the fixes)
The same six testers re-checked their items on fresh simulator screens (each setup re-shot from the merged round 3 build, then again after the fixes below). The Status column above is the result. New problems they found, all fixed unless marked open:

- Hormonal IUD with no period logged got the irregular/PCOS view ("your cycles vary a lot", "log the first day of your next period"). Now it gets the method's own view (`CycleDisplay.make`, tested).
- The example stress day drew hours that hadn't happened yet and hours she was asleep for. Now it shows only past, awake hours.
- Energy listed two sleep debts (5h 37m and 5h 06m). The score's row is now "Debt from earlier nights", since last night has its own row.
- "Your latte now would still be about 140 mg at bedtime" for a 130 mg drink. It now says that's the total, "with what you've already had".
- The sick check said "All clear" and then "part of this could be your cycle". The cycle note and the tips heading now follow the result.
- Under eating-disorder history, Fitness still showed fitness age and a falling history line, and Water drew a "steady pace" line. All hidden now. The Body tile shows VO₂ max as a number.
- The Fitness tile said "Age 26" with no age set. It now says "Fitness age 26". Settings and Fitness both say "Compared with: Women / Men", with nothing preselected.
- "This week" sat over last night's sleep and today's drinks, so it's now "At a glance". Today's ring says "7h 21m", not "7.3h".
- The stress scale used two vocabularies. The Stress screen now uses the Log's words.
- Water: "about 2½ bottles" for 2.67 is now "about 2¾" (quarters). The "Add" and "Set" buttons were squeezed into letters.
- Large text: the quick-log drink card broke "Latte" into letters (it stacks now), the common-drink chips scrolled sideways (they wrap now), and Today's ⓘ covered its labels.
- Polish: "1 points", "worst day" (now "lowest day"), "social jetlag", the weekend shift without am/pm, "hrv" in lowercase, and "· Off" wrapping alone on the alarm chip.

Still open:
- Large text: the sleep-stage axis, long phase names ("Follicu / lar"), "Natural cycle" clipped in Settings, ring captions touching their rings, a few "…" truncations in Settings and Wins, the floating gear over card text.
- Contrast in light mode: REM bars and Awake ticks under 3:1 on the grey track, grey axis labels at 3.2–3.5:1, and an almost invisible empty progress track on Wins.
- U1: the water goal doesn't rise on training days. U7: the energy curve is flat over a small range. N16: stage differences to the minute.
- Not built yet: friend streaks, a doctor-ready export, pill-taken logging and reminders.

## Works on real screens
Pack dates (pill 18 → break Sat Oct 31; 24+4 switch), withdrawal-bleed wording, no ovulation predictions on the pill, caffeine on the pill (~9h half-life matches the copy), the 12:30am bedtime used everywhere and "Tue night" labelling, smart alarm off by default, water in oz with no ml on screen, chart scrubbing (a sideways drag scrubs, a vertical drag scrolls the page), energy left agrees from phone to Watch, irregular cycle copy (no countdown, no "late", an honest note), 988 buttons in light mode, the calories toggle explains why it's off, exercise tips swapped out under ED history, example data labelled on every phone and Watch screen, no cycle preselected, conditions say what they change, ⓘ on Today's jargon, spoken chart summaries, no unlabelled buttons.

## Still untested
After midnight and the 4am rollover (a 12:15am latte, greeting, water), the Nov 1 clock change (plan screen, alarm window, recorded wake), spotting-only flow logging, workouts vs stress, the sick check after a hard training day, the smart alarm ringing, Watch gestures (page swipe over the chart, crown), and Watch water logging.
