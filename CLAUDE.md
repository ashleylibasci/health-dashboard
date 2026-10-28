# Health Dashboard

The native iPhone + Apple Watch app is in `health-dashboard-app/` (read its `HANDOFF.md` and `TEST-FINDINGS.md` first). `ios/` is the earlier version and the root folder is the original web app: don't change, delete or overwrite either without asking Ashley.

## After every change to the app

Do all of these, in order, every time:

1. **Build.** If files were added or removed, regenerate the project first (`xcodegen generate`; `./setup.sh` does the same and also opens Xcode). Fix every error and warning.
   ```bash
   cd health-dashboard-app
   xcodebuild -project HealthDashboard.xcodeproj -scheme HealthDashboard -configuration Release \
     -destination 'platform=iOS,id=00008160-000D146A00434036' \
     -derivedDataPath DerivedData -allowProvisioningUpdates build
   ```
2. **Install and launch on Ashley's iPhone and Watch.** The Watch app is embedded in the iPhone app and installs on her paired Watch along with it.
   ```bash
   xcrun devicectl device install app --device 00008160-000D146A00434036 \
     DerivedData/Build/Products/Release-iphoneos/HealthDashboard.app
   xcrun devicectl device process launch --device 00008160-000D146A00434036 \
     com.ashleylibasci.healthdashboard
   ```
   If the Watch shows up in `xcrun devicectl list devices`, launch `com.ashleylibasci.healthdashboard.watchkitapp` on it the same way. If not, say so and ask Ashley to open the app on the Watch.
3. **Commit and push to GitHub** (`origin` → https://github.com/ashleylibasci/health-dashboard, branch `main`). This repo is public: never commit health data, exports, the zip or anything personal.

If any step fails (phone locked or not connected, signing, a failing build), stop and tell Ashley which step failed and why; don't skip ahead to commit and push.

## Notes
- The app installs as **Health Dashboard** (`com.ashleylibasci.healthdashboard`, Watch `….watchkitapp`, widgets `….widgets` and `….watchkitapp.widgets`). Since Oct 27, 2026 (Ashley's decision) it replaces the old app from `ios/`, which used the same IDs: there is one app on her phone. The interim `com.ashleylibasci.healthdashboard.next` ("Health Next") is retired; never build it again.
- Signing: team `93C3VKR4FJ` (Ashley Libasci, Personal Team) is set in `project.yml` for both targets. A free team's install expires after 7 days; reinstalling renews it.
- Ashley's phone always gets a **Release** build: a Debug build runs the health math unoptimized and scrolling and taps stutter (Oct 28, 2026).
- Logic tests: `cd health-dashboard-app/Packages/HealthCore && swift test`.
