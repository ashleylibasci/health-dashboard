# Ideas backlog

From the brainstorm on Oct 28, 2026 (the women's health experts and the app-structure design team). Ashley picked 52 ideas and all 31 small fixes to build and preview; these are the ones she didn't pick, kept for her to go through later.

Effort: S about a day, M a few days, L a week or more. Value 1–5 for Ashley.

## Women's health experts

### Pill and pack

- **H-A3 Break-week planner for exams and trips** ★ top 5 #4 · effort S · value 4/5. A strip showing the next three packs, with her imported exams, trips and breaks on it. Where a bleed lands on finals or a trip, a gentle line: "Your break week overlaps finals. Running packs back to back is a safe option many people choose; ask your prescriber." *Why:* ACOG considers extended and continuous combined-pill use safe. The app already supports ending a pack early, so this just makes the choice visible ahead of time.
- **H-A12 Blood-pressure note for estrogen pills** · effort S · value 2/5. An optional yearly line: "Estrogen pills can raise blood pressure a little; a pharmacy machine check is quick." It reads blood pressure from Health if she has any. *Why:* CDC US MEC uses blood pressure to decide whether an estrogen pill is suitable.

### Mood, stress and exams

- **H-B2 Words-only mode for hard weeks** · effort S · value 4/5. A switch (or automatic during exam weeks) that replaces scores on Today with words: "Take it steady", "Bed by 11:50pm". The numbers stay one tap away. *Why:* anxious score-checking makes sleep worse (orthosomnia, Baron 2017). Exam week is when that risk peaks.
- **H-B5 Your campus numbers** · effort S · value 3/5. She saves her own student-health and counseling-center numbers once, and they show in the guide's Help now section. *Why:* students don't know where these numbers are at 2am. This adds no crisis-line content; it holds only the numbers she chooses to save.

### Caffeine, alcohol and fuel

- **H-D7 Meal rhythm taps (contested)** · effort M · value 2/5. Optional "ate breakfast / lunch / dinner" taps, with no foods and no numbers. Over time they line up against low-energy check-ins. It's off under eating-disorder history. *Why:* low energy availability is common in active college women. Cole's objection stands: it can become a restriction scorecard.

### Data, privacy and export

- **H-G2 Face ID lock** · effort S · value 4/5. An optional Face ID lock on the app, or just on Cycle, Mood and Conditions. *Why:* cycle and mood data are sensitive, and phones get passed around. The data already stays on the phone, and this closes the last gap.

### Campus health checklist

- **H-H1 Yearly checklist** · effort S · value 3/5. A small opt-in list in the guide: flu and COVID shots each fall, HPV vaccine through age 26, MenB, and the yearly chlamydia and gonorrhea screen recommended for sexually active women under 25. Each item has a "done" tick. *Why:* USPSTF and CDC recommendations, and students lose track of all of these. It's a preventive checklist, not sick-check care content.
- **H-H2 "Can I go to class?"** · effort S · value 2/5. In the sick check: "Back to class when you're 24 hours fever-free without fever reducers and getting better." *Why:* this is about not spreading flu around the dorm (CDC respiratory-virus guidance), not about when to see a doctor. The team ranks it low until Ashley says she wants more sick-check content.

## Design team

### Today as a daily home

- **D-T6 Tonight card extras in the week before a clock change** · effort S · value 3/5. A line on Tonight reads "Clocks go back Sun · start 15 min earlier tonight", plus a "Staying up late?" row. *Why:* the clock change already lives on Sleep and Body clock. Tonight is where she plans tonight.
- **D-T7 Day-3 hello card** · effort S · value 2/5. A one-time card on day 3: "Add a widget, open it on your Watch, set your conditions." It dismisses for good. *Why:* these features are invisible unless she digs into Settings.

### Delight and motion

- **D-M1 Zoom from Today into detail** ★ top 5 #5 · effort M · value 4/5. Tapping the recovery ring, the Tonight card or a tile grows that element into the detail screen's hero, and it shrinks back on Back. iOS 18 zoom transition, with a cross-fade on iOS 17 and with Reduce Motion. *Why:* it's the "fluid" she asked for, and she always knows where she came from.
- **D-M3 Logging that feels good** · effort S · value 3/5. The water bottles fill with a liquid wobble, the latte cup fills, and the goal gets a small sparkle (symbol effects, existing Motion tokens). *Why:* logging is her most frequent action, and today it's a number change plus a toast.
- **D-M4 Charts draw in and morph** · effort S · value 3/5. Lines trace in on first appearance. Switching HRV → Resting HR, or Score → Energy left, morphs the line instead of snapping. *Why:* it reads as one continuous chart, not a reload.
- **D-M5 Collapsing header with the answer pinned** · effort M · value 3/5. While she scrolls, the large title shrinks into the nav bar as "Sleep · 7h 21m", so the answer stays visible. *Why:* on long detail screens she never loses the headline.
- **D-M6 Evening dim** · effort S · value 2/5. After her wind-down time the app's backgrounds shift slightly warmer and darker. The colour follows the time of day, never a score. *Why:* it matches her mood at night, and it pairs with Today following the clock.

### Widgets, Lock Screen, Live Activities, Watch

- **D-W5 Energy widget and complication with a "now" dot** · effort M · value 4/5. A small curve with a dot and "57 · dip till 6pm". *Why:* it's the most glanceable number she has.
- **D-W7 Pick what a widget shows** · effort M · value 3/5. Long-press → Edit Widget → Recovery / Energy / Sleep debt / Water. *Why:* one widget slot can serve whichever number she cares about this month.

### Onboarding, empty and learning states

- **D-L2 Empty states with one action** · effort S · value 3/5. No data means one friendly line plus a button ("No stress check-ins yet · Rate today"). No empty chart grids, no "None yet" rows stacked three deep. *Why:* fewer boxes that say nothing.
- **D-L3 Onboarding ends on her data** · effort M · value 3/5. The last step animates "Reading your last 30 nights… 27 nights found, HRV from your Watch ✓", then drops her on Today. *Why:* it shows the app is already working for her, instead of ending on a form.
- **D-L4 First name and greeting** · effort S · value 3/5. Onboarding asks for a first name: "Good evening, Ashley", with an initials avatar (or a gear until a name is set). *Why:* warmth, and the person glyph never said "Settings".

### Charts

- **D-G2 Range picker: W / M / 6M** · effort M · value 4/5. On HRV, Resting HR and Sleep, like Apple Health (today they're fixed at 14 or 7 nights). *Why:* she can see whether this month is better than last.
- **D-G3 Pack overlay on trends** · effort M · value 4/5. The break week is shaded behind the HRV, Resting HR and sleep charts, with the legend chip "Break week". *Why:* she can see her own pill rhythm in her data, the most Clue-like thing we could add.
- **D-G4 Compare, don't switch** · effort M · value 3/5. The HRV page's segmented control becomes "Compare with: Resting HR / Sleep", overlaying a faint second line. *Why:* it keeps "detail links go down, not sideways" and shows the relationship.
- **D-G5 At rest, the readout adds something** · effort S · value 3/5. Before she touches the chart, the readout shows the period summary ("14-night average 46 ms · range 42–49"), not a repeat of the hero sentence. *Why:* today HRV, Resting HR, Body clock, Stress and Cycle all say the hero twice.

### Navigation, search and organisation

- **D-S1 Search everything** · effort M · value 4/5. Pull down on any tab for one search across screens, settings and Health guide articles ("calendar", "pill", "HRV"). *Why:* her original "I can't find where to connect my Google Calendar" is a search problem. The guide is already searchable, but only from inside Settings.
- **D-S2 Quick log from anywhere** · effort M · value 3/5. Long-press the Log tab for a small menu: latte, +1 bottle, period, stress. *Why:* a two-second log from any screen, while the Log tab stays the full form.
- **D-S3 Health guide gets a front door** · effort S · value 3/5. A book icon in the tab header (next to the avatar), or a "Learn" row at the bottom of Body, instead of being the first row of Settings. *Why:* a library isn't a setting, and every "Learn more" leads there anyway.
- **D-S4 Body gets a summary** · effort S · value 3/5. Body is the only tab without a SummaryHeader. Add one line: "Signals look like your usual · pill day 18 · energy 57 now". *Why:* the same summary-first rule on every tab.

### Personalisation and insight

- **D-P1 Your week as a story** · effort M · value 4/5. Sunday evening, "Your week" opens as five swipeable cards: best night, energy pattern, caffeine habit, pack week, one thing to try. *Why:* a weekly recap people actually look forward to (Whoop's and Oura's are their most-opened screens).
- **D-P2 Patterns** · effort L · value 4/5. Cards like "Nights after 2+ drinks, your HRV is 9% lower" or "Exam weeks cost you 40 min of sleep", shown only once the data supports them. *Why:* turns logging into answers, which is Bevel's and Whoop's best feature.
- **D-P3 Tags in the check-in** · effort M · value 3/5. The morning check-in adds optional chips (exam, late study, workout, party, sick) that feed Patterns. *Why:* a college-life context that no watch can measure.
- **D-P4 Pin and reorder At a glance tiles** · effort M · value 3/5. Long-press a tile → Edit: hide Stress, add Pill or Energy. *Why:* a small, safe kind of personalisation.
- **D-P5 Alcohol gets its own colour** · effort S · value 2/5. A ninth hue (deep berry), tested against pink and coral in both modes. *Why:* today alcohol shares purple with sleep.

### Notifications

- **D-N1 One morning note** · effort M · value 4/5. At about 45 minutes after waking: "68 · take it steady · pill day 18 · bed by 11:50 tonight", with Log latte and +1 bottle buttons. Other nudges stay off unless she turns them on. *Why:* one notification she reads, not five she swipes away.
- **D-N2 Notifications that do the thing** · effort S · value 4/5. The pill reminder has "Taken" and the wind-down nudge has "Turn on Watch alarm", both acting without opening the app. *Why:* one tap from the Lock Screen.
- **D-N3 Bedtime reminder as a normal setting** · effort S · value 3/5. Settings → Sleep & alarm → "Wind-down reminder · 30 min before bed", no longer hidden in the clock-change plan. *Why:* it's the setting people look for first.
- **D-N4 Settings by moment, not by feature** · effort S · value 2/5. Notifications grouped as Morning / Daytime / Bedtime, each with one switch. *Why:* easier to reason about than a list of features.

### Accessibility

- **D-A1 Rows instead of dials at the largest text** · effort S · value 4/5. At accessibility sizes, the three dials under recovery become MetricRows. Today drops from about 4 screens to about 2.5. *Why:* at the largest text size, Today is mostly stacked rings.
- **D-A2 Quiet icons** · effort S · value 3/5. Hide decorative SF Symbols from VoiceOver everywhere (see flaws 11–12), and give each chart a one-sentence summary label. *Why:* VoiceOver currently reads "Search Document", "Waveform" and "love".


## Built, previewed and dropped (Oct 29, 2026)

Ashley saw these working and chose not to keep them. Each one's code is in git history (reverted, not lost) if she changes her mind.

- **H-B4 Bedtime brain dump.** A "Tomorrow's list" box in tonight's sleep plan, cleared after a week. Commits d8b3d18 and 9e6ec91.
- **H-D4 Drink size up or down.** A Size choice (small, regular, large, extra large, matching short, tall, grande, venti) on the caffeine card, scaling the mg. Commit d05931e.
