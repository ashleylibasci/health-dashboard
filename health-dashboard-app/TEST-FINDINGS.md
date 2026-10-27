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
| Watch | `syncedAt: now` on stale data; Watch showed recovery when phone had none; no cold-launch snapshot; weekend alarm arming; sick alert invisible in foreground; nudges only on open days | `lastRefreshed` stamp; optional recovery; snapshot request on launch/activation; evening "open your Watch app" reminder; notification delegate; tomorrow's nudges |
| Math | Last night counted twice in energy; rebound biased high; "late nights" = weekends; absolute 600 kcal training; partial-day HRV; recap habits circular; weak confidence gate | Debt from prior nights; rebound weight scaled; within-weekday comparison; relative training; overnight HRV; recap labelled as estimated, habits from check-ins; stricter gate, median baselines |
| First run / large text | Accuracy tips thought Health wasn't connected; hybrid real/example screens; clipping in rings, gauges, chips, dial, legends, fixed-width fields; text-size change reset the app | `healthConnection`, real nights in history, "N of 14"; scaled/stacking layouts; no forced rebuild |
| Tone & colour | 988 buttons low contrast; drinks tiles judged by colour; future pills faint; 8pt phase letters | Filled 988 buttons; words not colours; stronger borders; 11pt letters + strip labels |

## Still open (known, not bugs)
- Pill "Taken" logging and pill reminders (in the design, not built; nothing claims them).
- Doctor-ready export (current export is raw JSON).
- Friend streaks (removed).
- Everything was verified by reading code and type-checking against stand-in SwiftUI modules, plus 69 HealthCore unit tests. Nothing has run on a device or simulator yet. **The Watch files were syntax-checked and read line by line but not type-checked.** First job on a Mac: build both targets and fix anything the real SDK flags.
