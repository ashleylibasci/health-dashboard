# Health Dashboard for iPhone

The phone version of the dashboard, in the Morning light design. It reads sleep,
resting heart rate, HRV and caffeine straight from Apple Health every time it
opens, so there's nothing to export. Exams come from Google Calendar through the
same secret iCal link the web dashboard uses.

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
6. Open the app, tap **Connect Apple Health** and allow everything it lists.

With a free Apple ID, the app stops opening after 7 days; plug in and press Run
again to renew it. A paid Apple Developer account ($99/year) removes that limit.

## Calendar

Tap the **A** in the top corner → paste the **Secret address in iCal format**
from Google Calendar (Settings → your calendar). It's stored in the phone's
Keychain. The app checks the calendar when it opens and every 30 minutes while
it's open.

## Testing without a phone

In the simulator, launch with the `-demo` argument (Product → Scheme → Edit
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
| `Views/` | Today, Sleep, Body, Exams and Settings in Morning light |
