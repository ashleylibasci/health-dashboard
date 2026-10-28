# Handoff: Health Dashboard

For a Claude Code session running on Ashley's Mac. Read this first, then README.md and TEST-FINDINGS.md.

## What this is
A native iPhone (iOS 17) + Apple Watch (watchOS 10) app in SwiftUI. It reads Apple Health and works out:
- your sleep need from how your body responds,
- your best wake time and a smart alarm on the Watch,
- your energy curve through the day,
- caffeine timing, cycle and birth control, stress, recovery, illness signals, fitness age, water (in oz), drinks and late nights.

Dark by default, with a light mode. Designs: the "Health Dashboard Redesign" canvas on claude.ai (dark `Night*` and light `Light*` boards).

## Layout
- `project.yml`: XcodeGen spec. Run `./setup.sh` (or `xcodegen generate`) after adding or removing files. The app installs as **Health Dashboard**, `com.ashleylibasci.healthdashboard` (+ `.watchkitapp`, `.widgets`, `.watchkitapp.widgets`), replacing the old app from `ios/` (same IDs) since Oct 27, 2026. It reads the old app's calendar sign-in from the Keychain and leaves an alarm the old app scheduled alone until its own backup is on. Signing team `93C3VKR4FJ` is set for every target, so Xcode never asks.
- `HealthDashboardUITests/TestRound.swift`: the hands-on test round. It walks onboarding, every tab, the main screens, the pack setting, a coffee at a custom time, water and the chart drags in dark, light and the largest text size, saving a screenshot plus the element tree at each step (`TEST_RUNNER_SHOT_DIR=/folder xcodebuild test …`).
- `Model/DemoMode.swift`: Debug-only launch arguments (`-demo`, `-demoSick`, `-demoCycle pill|hormonalIUD|natural|copper|irregular`, `-demoConditions`, `-resetData`) that show labelled example data without asking Apple Health. The Watch takes `-demo` and `-page 0…3`.
- `Packages/HealthCore`: pure Swift logic with XCTest. Run `swift test` there. This is where the math lives: sleep need and debt, the energy model, wake planner, caffeine, cycle and birth control (`CycleDisplay`), stress, illness, fitness age, streaks, and wall-clock time helpers.
- `HealthDashboard/`: the iPhone app.
  - `Model/AppModel.swift` holds all state. `refresh()` reads Health; it runs on launch and whenever the app becomes active.
  - `Model/DataStore.swift` holds saved settings and logs as JSON. Decoding is forgiving.
  - The `AppModel+*.swift` extensions hold derived values.
  - `Model/Explanations.swift` has the plain-language text behind every ⓘ.
  - `Views/` holds the screens. `Views/Components/` has the shared pieces: `Screen`, `Card`, `InfoButton`, `HowWeGotThisLink`, `ChartReadout`, `chartScrub` + `ScrubSurface` (UIKit touch layer for charts), `SampleDataBanner`, and `Font.scaled` (Dynamic Type).
  - Design system (from the Oct 28 design review): colours, type and tokens in `Shared/Theme.swift` and `Views/Components/ScaledFont.swift` (one hue per feature; `TypeRole` roles via `.font(.screenTitle)` etc.; `Space`, `Radius`, `Sizes`); motion in `Shared/Motion.swift` (`withMotion`, `.motion`, `.buttonStyle(.pressable)`, Reduce Motion fallbacks); `TabHeader.swift` (the header on all four tabs), `LogFeedback.swift` (Undo toast after any log), chart descriptors in `ChartAudioGraph.swift`. Use these instead of literal sizes, colours and animations.
  - Screen structure (from the Oct 28 structure review; the layout order is at the top of `SummaryHeader.swift`): `SummaryHeader` (the 2-second answer), `RowCard` + `MetricRow` / `ExpandRow` / `RowDivider` (`Rows.swift`), `CalloutBar` (one urgent line, only while its trigger fires) and `.bottomSheet` (`CalloutBar.swift`), `LearnMoreRow` into the Health guide. Charts: give `ChartReadout` every note it can show (`detailSlots`) so it never changes height while scrubbing, write snapped selections only (`$selection.snapping { … }`), pass `feedbackKey` to `chartScrub` on dense charts, keep labels off the plot (axis gutter or legend), and keep a card's scrub state inside the card (`EnergyCurveCard`).
  - Health guide: `Views/Guide/`. `HealthGuide.sections` (Help now first), one file per section (`Guide+Sleep.swift` …) holding `GuideArticle`s; `HealthGuideView` (searchable, first row in Settings), `GuideArticleView`, and `LearnMoreRow("Learn more about sleep", article: .troubleSleeping)` to link one article. Copy moved into the guide moves word for word.
  - Safety content: `Views/BodyLog/CycleSafety.swift` (missed-pill rules, medicines and the pill, heavy bleeding, red flags, 90-day and RED-S notes). Heart and cycle-aware recovery/stress/sick logic: HealthCore `HeartSignals.swift` and `Model/AppModel+Heart.swift`.
  - `Services/` has the clock-change bedtime reminders, the peak/dip and sick notifications, and the features ported from the old app:
    - `BackgroundHealth.swift`: Apple Health wakes the app when sleep, caffeine, water, periods, resting HR, HRV or wrist temperature change; the app refreshes and updates the Watch. Off on example data and in demo mode.
    - `PhoneBackupAlarm.swift`: an AlarmKit iPhone alarm at the smart alarm's latest time, cancelled when she stops the Watch alarm (iOS 26.1+; the setting says so on older iOS).
    - `CalendarImport.swift`: exams from Apple Calendar (EventKit), Google Calendar (OAuth with PKCE, refresh token in the Keychain) or a secret iCal link (`ICSFeed`, address in the Keychain). Imported exams are keyed by `AppData.Exam.source`, so re-imports never duplicate and never touch exams she added or edited. The card is in the exam list and Settings → Exams.
    - `Shortcuts.swift`: Siri / Shortcuts / Spotlight "Log a latte" (`Shared/LogLatteIntent.swift`).
- `HealthDashboardWidgets/`: Home Screen and Lock Screen widgets (Recovery, Cycle, Caffeine & water with a "log a latte" button, Bedtime streak). They read `WidgetSnapshot` from the App Group.
- `HealthDashboardWatchWidgets/`: Watch-face complications (Recovery, Cycle, Caffeine, Bedtime).
- `HealthDashboardWatch/`: Watch pages and `SmartAlarm.swift` (WKExtendedRuntimeSession smart alarm).
- `Shared/`: HealthKit access (`HealthKitService`), phone↔Watch sync (`WatchSync`), `WidgetSnapshot`, the latte intent and the theme.
- App Group: the old app's `group.com.ashleylibasci.healthdashboard` (a free team can't register a new one), with this app's own keys (`next.widgetSnapshot.v1`, `next.pendingDrinks.v1`) so it never reads the old app's leftover widget numbers.

## Conventions
- Plain language for a college student; every number and term gets an ⓘ. Method details go behind "Learn how we got this number", never on the main page.
- Every chart is scrubbable (`chartScrub`): a tap picks a point, a sideways drag moves along the chart, and a vertical drag scrolls the page.
- The app day rolls over at 4am (`AppDay`). Times are `Minutes` relative to the wake day.
- Never claim a feature that isn't built. When data is missing, say so; never fall back to sample numbers on a real phone.
- Sample data (`SampleData.swift`) is used in the simulator and until Health has 14 nights. It is always labelled with `SampleDataBanner`.
- Water is stored in ml (as Apple Health stores it) and shown in oz.
- Ashley is on a combined pill. Birth control is handled by `CycleDisplay` (pack / suppressed / phases / irregular / overdue). The pack position is set in Settings → Cycle & birth control.

## History
1. Designs, then a native build delivered by zip. The app runs on her iPhone.
2. Feedback round:
   - every graph made interactive, many more explanations,
   - method sections moved behind links,
   - time-change plan fixed (never touches alarms),
   - caffeine and water editing restored, water in oz,
   - cycle colours fixed, birth control respected,
   - "Getting accurate numbers" checklist,
   - stress and other earlier features restored.
3. Test round 1: six simulated student testers (Maya on the pill, Jordan the night owl, Priya the runner/Watch user, Theo the first-timer at the largest text size, Sam the statistician, Riley with PCOS) read the code; ~120 findings, all fixed.
4. Test round 2: same testers re-checked and found ~60 smaller issues/regressions; all fixed. See TEST-FINDINGS.md (bottom section lists what's still open).
5. Ashley asked for: water in oz, choosing where she is in her pack in Settings (Settings → Cycle & birth control, also on the Cycle screen and in onboarding), bedtime and wake time at any hour.

6. Round 3 on the Mac (Oct 27, 2026): real builds, the simulator test round, and the six student testers (the "student-testers" BMad party) on real screens. Findings and their status are in TEST-FINDINGS.md. The old app's features were ported in the same session (see Layout).
7. Expert review (Oct 28, 2026): a women's health expert party and a design party (both in `_bmad/custom/bmad-party-mode.toml`) reviewed every calculation, message and screen. What changed and what's still recommended: EXPERT-REVIEW.md. The app is for women only (no male norms or options), and it replaced the old app on her phone under the old bundle IDs.

## Simulator test round
`HealthDashboardUITests/TestRound.swift`, one tester setup at a time, e.g.
```
TEST_RUNNER_SHOT_DIR=/folder TEST_RUNNER_DEMO_ARGS="-resetData -demoCycle pill" \
  xcodebuild test -project HealthDashboard.xcodeproj -scheme HealthDashboard \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -parallel-testing-enabled NO \
  -only-testing:HealthDashboardUITests/TestRound/test8ScreensDark
```
Xcode 27.1 can hang after the suite reports on this simulator; stop `xcodebuild` once the log says the suite passed or failed. Use a separate `-derivedDataPath` so it doesn't fight the device build.

## What a Mac session can do that the cloud couldn't
- Build and run in the Simulator:
  ```
  xcodebuild -scheme HealthDashboard -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
  ```
  Then `xcrun simctl` to install, launch and screenshot (`xcrun simctl io booted screenshot shot.png`).
- Do a hands-on test round on real screens. Check:
  - large text sizes (Settings → Accessibility → Larger Text in the Simulator),
  - light mode,
  - chart scrubbing inside scrolling pages,
  - the Watch app in a paired Watch simulator.
- Fix anything Xcode warns about. The cloud type-checked against stand-in SwiftUI modules, so real-SDK warnings or errors are possible, especially in `ScrubSurface.swift`, `ScaledFont.swift` and the Watch files.
- Push to her GitHub: the app lives in `health-dashboard-app/` of https://github.com/ashleylibasci/health-dashboard (public). See the repo-root `CLAUDE.md` for the build → install → commit → push routine.

## Verify first on the Mac
- Build both targets with the real SDK (Xcode 27.1 / iOS 27 SDK on her Mac; targets are iOS 17 / watchOS 10). The cloud only type-checked the iPhone app against stand-ins and syntax-checked the Watch app.
- Highest-risk files: `HealthDashboardWatch/SmartAlarm.swift`, `HealthDashboardWatch/Pages/EnergyPage.swift` (crown + tap), `Views/Components/ScrubSurface.swift` (UIKit gestures), `Views/Components/ScaledFont.swift`, `Services/Nudges.swift` (notification delegate).

## Not checked on a device yet
- The widgets and complications on a real Home Screen and Watch face, Siri "Log a latte", the AlarmKit backup ringing, and calendar import with real events.
- Google sign-in with real events (the OAuth client is made for `com.ashleylibasci.healthdashboard`, which the app now uses).

## Not built yet
- Friend streaks.
- A doctor-ready export (the current export is raw JSON).
- Condition-specific features beyond PCOS, PMDD (crisis line) and eating-disorder history (Conditions says so honestly).
- Pill-taken logging and pill reminders.
