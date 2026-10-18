# Health Dashboard for iPhone and Apple Watch

The phone version of the dashboard, in the Morning light design. It reads
Apple Health every time it opens (sleep and stages, heart rate, HRV, activity,
VO₂ max, cycle, wrist temperature, drinks, water and mood), so there's nothing
to export. Exams come from Google Calendar through its secret iCal link.

## What's in it

- **Welcome flow:** your name and birthday, cycle type, birth control,
  preferences, health conditions and water bottle size, then Apple Health (your
  full history) and Google Calendar.
- **Today:** recovery score and why, cycle day, sleep regularity, caffeine,
  fitness age, stress, exams, plus a getting-sick alert and "Why do I feel off?"
- **Sleep:** the week, weekend shift, sleep stages, late-night cost.
- **Body:** recovery, stress (with a 1-minute breathing exercise), energy and
  sleep debt, fitness age, the caffeine cutoff test, drinks, calories, cycle
  calendar and phases, pill pack, birth-control and condition pages, streaks.
- **Log:** lattes, espresso shots, energy drinks, alcohol (including shots),
  water by your bottle size in quarters, stress, period flow and symptoms, all
  saved to Apple Health.
- **Widgets:** recovery (Home and Lock Screen), a tap-to-log latte, bedtime
  streak and cycle day.
- **Apple Watch:** recovery, one-tap logging, tonight's bedtime (dark after
  8pm), cycle ring, the getting-sick heads-up, and watch-face complications.
  The phone sends the Watch a fresh summary each time you open the app.

## Put it on your iPhone

1. Open `ios/HealthDashboard.xcodeproj` in Xcode.
2. Xcode → Settings → Accounts → **+** → sign in with your Apple ID.
3. Click the **HealthDashboard** project (top of the left sidebar) → the
   **HealthDashboard** target → **Signing & Capabilities** → pick your name under
   **Team**. If Xcode says the bundle ID is taken, change the end of it
   (e.g. `com.yourname.healthdashboard`).
4. Plug in your iPhone, unlock it, and choose it in the device menu at the top of
   Xcode. The first time, the phone asks you to turn on **Developer Mode**
   (Settings → Privacy & Security → Developer Mode) and restart.
5. Press **Run** (▶). On the phone, trust yourself as a developer the first time:
   Settings → General → VPN & Device Management → your Apple ID → Trust.
6. Open the app and go through the welcome screens. When Apple asks how much
   Health data to share, choose **All Recorded Data** to bring in your history.
7. The Watch app installs with the iPhone app if your Watch is paired. Open
   it once on the Watch so it can receive today's numbers.

Widgets and the Watch app share data through an App Group. A free Apple ID
may not allow App Groups; if Xcode refuses to sign, the phone app still works
on its own (remove the App Group under Signing & Capabilities).

With a free Apple ID, the app stops opening after 7 days; plug in and press Run
again to renew it. A paid Apple Developer account ($99/year) removes that limit.

## Calendar

Tap the **A** in the top corner → paste the **Secret address in iCal format**
from Google Calendar (Settings → your calendar). It's stored in the phone's
Keychain. The app checks the calendar when it opens and every 30 minutes while
it's open.

## Testing without a phone

In the simulator, launch with the `-demo` argument (add `-demoSick` for the
getting-sick alert, `-demoPill` for the pill-pack screens, or `-screen cycle`,
`-screen stress` and so on to open one screen directly) (Product → Scheme → Edit
Scheme → Run → Arguments) to fill every screen with made-up data. Settings also
has an **Add sample data** button in the simulator, which writes made-up nights
into the simulator's Health app. Neither exists in the build that goes on your
phone.

`Cmd-U` in Xcode runs the tests for the sleep, weekend-shift, late-night,
calendar and exam-week math.

## Code map

| Path | What it does |
|---|---|
| `Health/HealthReader.swift` | Reads Apple Health |
| `Analysis/` | The same sleep math as the web dashboard, in Swift |
| `Calendar/ICS.swift` | Reads the Google Calendar feed and spots exams |
| `App/AppModel.swift` | Refreshes Health and the calendar, feeds the screens |
| `Views/` | Every phone screen in Morning light |
| `App/Insights.swift` | Turns Health data into what each screen shows; logging; notifications |
| `App/Profile.swift` | The profile from the welcome flow |
| `Shared/` | Colors and fonts, the widget/Watch summary, the latte action |
| `HealthDashboardWidgets/` | Home Screen and Lock Screen widgets |
| `HealthDashboardWatch/` | The Watch app |
| `HealthDashboardWatchWidgets/` | Watch-face complications |
