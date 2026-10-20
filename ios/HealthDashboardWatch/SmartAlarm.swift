import CoreMotion
import WatchKit

/// The smart alarm: a watchOS smart-alarm session that starts up to 30 minutes before her latest
/// wake time, watches wrist movement, and taps her awake at the first sign of light sleep (or at
/// the latest time if that never comes). The app sleeps the rest of the night, so it costs
/// almost no battery.
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
    /// "Woke you at 7:22, 23 min early" from the last alarm.
    private(set) var lastResult: String? { didSet { UserDefaults.standard.set(lastResult, forKey: "smartAlarmLast") } }
    var error: String?

    private var session: WKExtendedRuntimeSession?
    private let motion = CMMotionManager()
    private var samples: [(x: Double, y: Double, z: Double)] = []
    private var watchTask: Task<Void, Never>?

    override init() {
        let d = UserDefaults.standard
        plan = d.data(forKey: "smartAlarmPlan").flatMap { try? JSONDecoder().decode(SmartAlarmPlan.self, from: $0) }
        armedFor = (d.object(forKey: "smartAlarmArmedFor") as? Date).flatMap { $0 > .now ? $0 : nil }
        lastResult = d.string(forKey: "smartAlarmLast")
        super.init()
    }

    var isArmed: Bool { armedFor.map { $0 > .now } ?? false }

    // MARK: Setting it

    /// Schedules the next window. Only works while the app is open, which is why Stop re-arms
    /// the next morning's alarm straight away.
    func arm(_ plan: SmartAlarmPlan) {
        self.plan = plan
        error = nil
        session?.invalidate()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: plan.windowStart(after: .now))
        session = s
        armedFor = plan.nextLatest(after: .now)
    }

    func turnOff() {
        plan = nil
        armedFor = nil
        session?.invalidate()
        session = nil
    }

    /// The system launched the app for a scheduled session (see `WatchAppDelegate`).
    func adopt(_ s: WKExtendedRuntimeSession) {
        s.delegate = self
        session = s
    }

    // MARK: The window

    nonisolated func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        Task { @MainActor in self.startWatching(s) }
    }

    private func startWatching(_ s: WKExtendedRuntimeSession) {
        session = s
        // Turned off after this was scheduled, and the old session couldn't be reached to cancel it.
        guard let plan, let latest = armedFor else { s.invalidate(); return }
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
            let early = Int(latest.timeIntervalSinceNow / 60)
            lastResult = early >= 1
                ? "Woke you at \(Date.now.formatted(date: .omitted, time: .shortened)), \(early) min early, in light sleep."
                : "No light sleep in the window, so it woke you at \(plan.latestText)."
            ring()
        }
    }

    private func ring() {
        motion.stopAccelerometerUpdates()
        watching = false
        ringing = true
        session?.notifyUser(hapticType: .notification) { next in
            next.pointee = .notification
            return 3
        }
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
        if let plan, plan.repeats { arm(plan) }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {
        // The 30 minutes are almost up: ring now rather than miss the alarm.
        Task { @MainActor in if !self.ringing { self.watchTask?.cancel(); self.ring() } }
    }

    nonisolated func extendedRuntimeSession(_ s: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
        Task { @MainActor in
            guard self.session === s else { return }
            self.watchTask?.cancel()
            self.motion.stopAccelerometerUpdates()
            self.watching = false
            self.ringing = false
            self.session = nil
            if reason == .error || reason == .sessionInProgress {
                self.armedFor = nil
                self.error = error?.localizedDescription ?? "The Watch couldn’t set the alarm. Try again."
            }
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
}
