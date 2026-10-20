import CoreMotion
import UserNotifications
import WatchKit

/// The smart alarm: a watchOS smart-alarm session that starts up to 30 minutes before her latest
/// wake time, watches wrist movement, and taps her awake at the first sign of light sleep (or at
/// the latest time if that never comes). The app sleeps the rest of the night, so it costs
/// almost no battery.
///
/// watchOS only lets the app schedule a session while it's open and active, one at a time. So a
/// plan sent from the iPhone waits until the Watch app is next open, and a repeating alarm re-arms
/// whenever the app opens. A plain notification at the latest time backs up every alarm, in case
/// the session never runs.
@MainActor
@Observable
final class SmartAlarm: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = SmartAlarm()

    var plan: SmartAlarmPlan? { didSet { save(plan, "smartAlarmPlan") } }
    /// The latest wake time the scheduled session is for. Nil when nothing is set.
    private(set) var armedFor: Date? { didSet { UserDefaults.standard.set(armedFor, forKey: "smartAlarmArmedFor") } }
    /// Buzzing right now, waiting for Stop.
    private(set) var ringing = false
    /// Inside the window, watching for light sleep.
    private(set) var watching = false
    /// Waiting for the Watch app to be open so it can schedule the alarm.
    private(set) var arming = false
    /// "Woke you at 7:22, 23 min early" from the last alarm.
    private(set) var lastResult: String? { didSet { UserDefaults.standard.set(lastResult, forKey: "smartAlarmLast") } }
    /// Movement in each 30-second epoch of the last window, for the graph on the alarm page.
    private(set) var lastWindow: [Double] = [] { didSet { UserDefaults.standard.set(lastWindow, forKey: "smartAlarmWindow") } }
    var error: String?

    private var session: WKExtendedRuntimeSession?
    private let motion = CMMotionManager()
    private var samples: [(x: Double, y: Double, z: Double)] = []
    private var watchTask: Task<Void, Never>?
    /// Bumped by each `arm`, so only the newest request updates the state.
    private var armGeneration = 0
    /// Whether the current session's window has begun.
    private var windowStarted = false
    private static let backupID = "smartAlarmBackup"

    override init() {
        let d = UserDefaults.standard
        plan = d.data(forKey: "smartAlarmPlan").flatMap { try? JSONDecoder().decode(SmartAlarmPlan.self, from: $0) }
        armedFor = (d.object(forKey: "smartAlarmArmedFor") as? Date).flatMap { $0 > .now ? $0 : nil }
        lastResult = d.string(forKey: "smartAlarmLast")
        lastWindow = d.array(forKey: "smartAlarmWindow") as? [Double] ?? []
        super.init()
    }

    var isArmed: Bool { armedFor.map { $0 > .now } ?? false }

    /// Set but not scheduled yet: from the iPhone while the Watch app was closed, or a repeating
    /// alarm whose next morning hasn't been scheduled.
    var isWaiting: Bool { plan != nil && !isArmed }

    var status: WatchAlarmStatus {
        if let armedFor, isArmed { return WatchAlarmStatus(state: .armed, latest: armedFor, plan: plan) }
        if let error, plan != nil { return WatchAlarmStatus(state: .failed, plan: plan, message: error) }
        if plan != nil { return WatchAlarmStatus(state: .waiting, plan: plan) }
        return WatchAlarmStatus(state: .off)
    }

    // MARK: Setting it

    /// Schedules the next window and waits to hear whether the Watch accepted it.
    ///
    /// Only works while the app is open and active. Otherwise the plan waits for `armIfWaiting`,
    /// and if a different time was already scheduled it stops counting as set, so the old time is
    /// cancelled (watchOS only allows that while active) instead of going off.
    @discardableResult
    func arm(_ plan: SmartAlarmPlan) async -> Bool {
        self.plan = plan
        error = nil
        // Changed (or re-set) during the wake window: finish this window properly first.
        if watching || ringing { endWindow() }
        guard WKApplication.shared().applicationState == .active else {
            if armedFor != plan.nextLatest(after: .now) {
                armedFor = nil
                removeBackup()
            }
            report()
            return false
        }
        // One request at a time; the newest one wins and the older ones leave the state alone.
        armGeneration += 1
        let generation = armGeneration
        arming = true
        defer { if generation == armGeneration { arming = false } }

        session?.invalidate()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        session = s
        windowStarted = false
        s.start(at: plan.windowStart(after: .now))
        // The answer comes back as the session's state (or an invalidation with an error).
        for _ in 0..<20 where s.state != .scheduled && s.state != .invalid {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if s.state == .invalid {
            // Give the invalidation callback a moment to say why.
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard generation == armGeneration, session === s else { return s.state == .scheduled }
        guard s.state == .scheduled else {
            s.invalidate()
            session = nil
            armedFor = nil
            if error == nil { error = "Your Watch didn’t accept the alarm. Try again with the app open." }
            report()
            return false
        }
        armedFor = plan.nextLatest(after: .now)
        await scheduleBackup(at: armedFor!)
        report()
        return true
    }

    func turnOff() {
        if watching || ringing { endWindow() }
        plan = nil
        armedFor = nil
        error = nil
        ringing = false
        session?.invalidate()
        session = nil
        removeBackup()
        report()
    }

    /// A plan (or nil, to turn it off) sent from the iPhone.
    func receiveFromPhone(_ plan: SmartAlarmPlan?) async {
        guard let plan else { turnOff(); return }
        await arm(plan)
    }

    /// The app just became active: schedule anything that's waiting, like a plan from the iPhone
    /// or tomorrow's repeat after the system's own alarm screen was used to stop it.
    func armIfWaiting() async {
        guard let plan, !isArmed, !arming, !ringing, !watching else { return }
        await arm(plan)
    }

    /// The system launched the app for a scheduled session (see `WatchAppDelegate`).
    func adopt(_ s: WKExtendedRuntimeSession) {
        s.delegate = self
        session = s
    }

    /// A plain notification at the latest time, so she's woken even if the session never runs.
    private func scheduleBackup(at date: Date) async {
        let center = UNUserNotificationCenter.current()
        removeBackup()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time to get up"
        content.body = "Your smart alarm’s latest time."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        try? await center.add(UNNotificationRequest(identifier: Self.backupID, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    private func removeBackup() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.backupID])
    }

    /// Tells the iPhone how the alarm stands.
    private func report() { WatchStore.shared.sendAlarmStatus(status) }

    // MARK: The window

    nonisolated func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        Task { @MainActor in self.startWatching(s) }
    }

    private func startWatching(_ s: WKExtendedRuntimeSession) {
        session = s
        windowStarted = true
        // Changed or turned off while the app couldn't cancel this session. Rather than wake her
        // at a time she no longer wants, end it with one quiet tap (a session that never taps
        // makes watchOS warn her) and let the current plan schedule itself when the app opens.
        guard let latest = armedFor, latest.timeIntervalSinceNow < 31 * 60 else {
            s.notifyUser(hapticType: .click, repeatHandler: nil)
            s.invalidate()
            session = nil
            report()
            return
        }
        watching = true
        samples = []
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 0.1
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let a = data?.acceleration else { return }
                MainActor.assumeIsolated { self?.samples.append((a.x, a.y, a.z)) }
            }
        }
        watchTask = Task {
            var detector = WakeDetector()
            while !Task.isCancelled, Date.now < latest {
                try? await Task.sleep(for: .seconds(30))
                let epoch = WakeDetector.movement(samples)
                samples = []
                if detector.add(epoch) { break }
            }
            guard !Task.isCancelled else { return }
            lastWindow = detector.epochs
            let early = Int(latest.timeIntervalSinceNow / 60)
            lastResult = early >= 1
                ? "Woke you at \(Date.now.formatted(date: .omitted, time: .shortened)), \(early) min early, in light sleep."
                : "No light sleep in the window, so it woke you at your latest time."
            ring()
        }
    }

    private func ring() {
        motion.stopAccelerometerUpdates()
        watching = false
        ringing = true
        // A one-off alarm is used up once it rings, however it's stopped (even from the system's
        // own alarm screen), so it never re-arms itself the next time the app opens.
        if plan?.repeats == false {
            plan = nil
            report()
        }
        removeBackup()
        session?.notifyUser(hapticType: .notification) { next in
            next.pointee = .notification
            return 3
        }
    }

    /// Ends the current window early (turned off or changed while it runs): stops watching and,
    /// if it hasn't buzzed yet, taps once so watchOS counts the alarm as delivered.
    private func endWindow() {
        watchTask?.cancel()
        watchTask = nil
        motion.stopAccelerometerUpdates()
        if watching { session?.notifyUser(hapticType: .click, repeatHandler: nil) }
        watching = false
        ringing = false
        session?.invalidate()
        session = nil
        armedFor = nil
    }

    /// Stops the buzzing and, if it repeats, sets tomorrow's alarm while the app is open.
    func stop() {
        watchTask?.cancel()
        motion.stopAccelerometerUpdates()
        ringing = false
        watching = false
        session?.invalidate()
        session = nil
        armedFor = nil
        if let plan, plan.repeats {
            Task { await arm(plan) }
        } else {
            plan = nil
            report()
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {
        // The 30 minutes are almost up: ring now rather than miss the alarm.
        Task { @MainActor in if self.session === s, !self.ringing { self.watchTask?.cancel(); self.ring() } }
    }

    nonisolated func extendedRuntimeSession(_ s: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
        let message = reason == .error ? Self.describe(error) : nil
        Task { @MainActor in
            // The reason goes to the iPhone too, even if a newer session has taken over since.
            if let message {
                self.error = message
                self.report()
            }
            guard self.session === s else { return }
            self.watchTask?.cancel()
            self.motion.stopAccelerometerUpdates()
            let ran = self.windowStarted
            self.watching = false
            self.ringing = false
            self.session = nil
            // Ended without ringing (an error, or the system stopped it): it's no longer set.
            if reason != .none { self.armedFor = nil }
            // A one-off alarm that ran is used up, whichever way it ended.
            if ran, self.plan?.repeats == false { self.plan = nil }
            self.report()
        }
    }

    /// Plain words for the reasons watchOS refuses a smart alarm.
    nonisolated private static func describe(_ error: (any Error)?) -> String {
        guard let error = error as NSError?, error.domain == WKExtendedRuntimeSessionErrorDomain else {
            return "Your Watch couldn’t set the alarm. Try again with the app open."
        }
        // The codes from WKExtendedRuntimeSessionErrorCode.
        return switch error.code {
        case 2: "Smart alarms can only be set up to 36 hours ahead."
        case 3: "Open Health Dashboard on your Watch to finish setting the alarm."
        case 6: "Background App Refresh is off for Health Dashboard. On your Watch: Settings → General → Background App Refresh, and turn it on."
        case 7: "This copy of the Watch app isn’t set up for smart alarms. Install the latest build from the iPhone."
        case 8: "Your Watch isn’t letting this app schedule alarms. Deleting and reinstalling the Watch app usually resets it."
        default: "Your Watch couldn’t set the alarm (error \(error.code)). Try again with the app open."
        }
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        UserDefaults.standard.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}

/// Hands scheduled smart alarm sessions to `SmartAlarm` when the system launches the app for one.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        MainActor.assumeIsolated { SmartAlarm.shared.adopt(extendedRuntimeSession) }
    }

    func applicationDidBecomeActive() {
        MainActor.assumeIsolated { Task { await SmartAlarm.shared.armIfWaiting() } }
    }
}
