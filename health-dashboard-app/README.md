# Health Dashboard

An iPhone and Apple Watch app that learns your sleep need, picks your best wake
time, and predicts your energy through the day, from your own Apple Health
data. Dark by default, with a light mode in Settings.

Designs: the "Health Dashboard Redesign" canvas on claude.ai.

## Run it

You need a Mac with Xcode 15 or later.

1. Unzip, then in Terminal:
   ```bash
   cd health-dashboard-app
   ./setup.sh
   ```
   This installs [XcodeGen](https://github.com/yonaskolb/XcodeGen) with Homebrew
   if needed, generates `HealthDashboard.xcodeproj`, and opens it.
2. Signing is already set up: `project.yml` sets Ashley's team (`93C3VKR4FJ`)
   for every target, so Xcode doesn't ask for a Team. The app installs as
   **Health Dashboard** (`com.ashleylibasci.healthdashboard`), replacing the
   older app from `ios/`.
3. Press Run with a simulator selected first; it doesn't need your phone.
4. To run on your iPhone and Watch, see "Your iPhone and Watch" below.

In the simulator, or until Apple Health has at least two weeks of sleep, the
app shows Ashley's sample data from the designs. For a simulator run that never
asks Apple Health, add `-demo` (or `-demoCycle pill`, `-demoSick` and others,
see `HealthDashboard/Model/DemoMode.swift`) under Product → Scheme → Edit
Scheme → Run → Arguments. On your iPhone it asks for
Apple Health access during setup, then uses your own data. Settings has
"Connect Apple Health" and "Use sample data".

## Updating to a new version

Your logs and settings are kept on the phone and carry over.

1. Unzip the new version in place of the old folder (or next to it).
2. Run `./setup.sh` again. New screens are new files, and Xcode only sees
   them after the project is regenerated.
3. Run.

## Your iPhone and Watch

1. Plug your iPhone into the Mac with a cable and tap **Trust** on the phone.
2. On the iPhone: Settings → Privacy & Security → **Developer Mode** → on (it restarts).
3. In Xcode's device menu at the top, pick your iPhone and press Run. The first time,
   on the phone go to Settings → General → VPN & Device Management and trust your
   developer certificate.
4. The Watch app installs with the iPhone app (keep the Watch paired and nearby). If
   it doesn't appear, open the Watch app on the iPhone and install Health Dashboard
   from "Available apps". The Watch also needs Developer Mode on (Settings →
   Privacy & Security on the Watch).
5. In the app, finish setup and allow Apple Health access.

A free Apple ID works for this, but the app expires after 7 days and needs
re-running from Xcode. A paid developer account ($99/year) lasts a year.

## GitHub

The app lives in `health-dashboard-app/` of
https://github.com/ashleylibasci/health-dashboard. Commit and push from the repo
root (`git add health-dashboard-app && git commit && git push`).

## How it's built

```
Packages/HealthCore/      All the logic, in plain Swift, with unit tests
HealthDashboard/          iPhone app (SwiftUI)
  Model/                  AppModel (everything on screen), DataStore, sample data
  Views/                  Screens, grouped by area
HealthDashboardWatch/     Apple Watch app (SwiftUI) and the smart alarm
Shared/                   Theme, Apple Health reader, phone ↔ Watch sync
project.yml               XcodeGen project definition
```

Run the logic tests with `cd Packages/HealthCore && swift test` (or in Xcode).

### What the logic does

| Feature | How it works | Where |
|---|---|---|
| Sleep need | Combines sleep on alarm-free nights after catching up ("rebound"), and the point where more sleep stops improving next-day HRV, resting heart rate, energy and reaction time (a hinge-model fit per measure). How you felt counts only as a cross-check, because people on short sleep say they feel fine while performance keeps dropping (Van Dongen et al., 2003). Starts near the adult average and narrows as nights add up; kept within 6–10 hours. | `SleepNeed.swift` |
| Tonight's need | Base need + sleep-debt payback + late luteal phase + hard day − naps. | `SleepNeed.swift` |
| Sleep debt | Last 14 nights; last night 15%, the rest weighted toward recent nights. | `SleepNeed.swift` |
| Best wake time | Candidate wake times are the ends of whole sleep cycles (cycle length learned from your nights) before your "up by" time. Each is scored on tonight's need and on the wake window that has worked best for you, learned from past mornings and how you felt. The smart-alarm window is the 30 minutes before it. | `WakeTime.swift` |
| Energy curve | The two-process model of sleep (sleep pressure + circadian rhythm timed from your body clock), with grogginess after waking. Gives peaks, the afternoon dip, second wind and the melatonin window. | `Energy.swift` |
| Body clock | Munich ChronoType Questionnaire method on your tracked sleep: sleep-corrected mid-sleep on free days, and social jetlag. | `Chronotype.swift` |
| Caffeine | 5-hour half-life; cutoff so under 25 mg is left at bedtime; coffee nap only when the dip starts before the cutoff. | `Caffeine.swift` |
| Clock change, exams, weekly recap, recovery, cycle phase | Planners and summaries built on the above. | `Planning.swift` |

### Smart alarm (Apple Watch)

When the smart alarm is on, the iPhone sends tonight's wake window to the
Watch. The Watch schedules a watchOS smart-alarm session for the start of the
window. During the window it watches wrist movement (over a rolling 2 minutes)
and heart rate (a rise of 4 bpm or more) for signs of light sleep. As soon as
either fires, or at the end of the window at the latest, it taps your wrist
until you press **Stop**, then tells the iPhone you're up.

Limits:
- watchOS only lets the app schedule the session while the app is open. Open
  the Watch app once before bed after changing the plan. The Tonight page
  says "Open this app the evening before to turn it on" if scheduling failed.
- A smart-alarm session runs for at most 30 minutes, so with a longer window
  it may ring a few minutes early (still inside the window).
- Apps can't read sleep stages live, so light sleep is a guess from movement
  and heart rate. Keep a backup alarm for anything you can't miss.

### Not built yet

- Home Screen widgets and Watch complications (WidgetKit)
- Stress, fitness age, calories, drinks, and "might be getting sick" screens from the designs
- Reaction-time test (the sleep-need screen sets a reminder only)
- Notifications before energy peaks and dips (the setting is saved but nothing is scheduled)
- Weekly recap from your own data: it needs a week of morning check-ins, so until then it uses the sample week
- A name field: Today greets you by `userName`, which nothing sets yet

### Privacy

Everything is computed on the phone. Check-ins, saved drinks and settings are
stored in the app's Application Support folder; caffeine and water are also
written to Apple Health. Nothing is uploaded.

*An estimate from your own data, not a medical device.*
