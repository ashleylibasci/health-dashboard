import SwiftUI
import WatchKit
import HealthKit
import CoreMotion
import HealthCore

// MARK: - Smart alarm

/// Wakes her when she starts stirring (often lighter sleep) inside tonight's wake window,
/// or at the end of the window at the latest.
///
/// How it works: a smart-alarm `WKExtendedRuntimeSession` (enabled by the
/// "alarm" WKBackgroundModes entry) is scheduled for the window's start. When
/// it starts, watchOS keeps the app running in the background; we watch wrist
/// movement (CoreMotion) and heart rate (HealthKit) as a proxy for light
/// sleep, then call `notifyUser(hapticType:repeatHandler:)` to buzz until she
/// taps Stop. watchOS can't give us sleep stages live, so this is an estimate.
@MainActor
final class SmartAlarmManager: NSObject, ObservableObject {
    static let shared = SmartAlarmManager()

    enum Status: Equatable {
        /// Off on the phone, or switched off on the Watch.
        case off
        /// On, but the phone hasn't sent a wake window.
        case noWindow
        /// The session is scheduled: listening from `start`, ringing by `end`.
        case scheduled(start: Date, end: Date)
        /// The next window is more than 36 hours away (watchOS can't schedule
        /// that far ahead), e.g. over a weekend off.
        case later(start: Date, end: Date)
        /// watchOS refused to schedule (usually because the app wasn't active).
        case needsForeground
        /// The window has started; watching for light sleep until `end`.
        case listening(end: Date)
        /// Buzzing until she taps Stop.
        case ringing(fromLightSleep: Bool)
        case woke(at: Date)
        case failed(String)
    }

    struct AlarmWindow: Equatable {
        var start: Date
        var end: Date
    }

    @Published private(set) var status: Status = .off {
        didSet { if status != oldValue { reportStatus() } }
    }
    /// The phone sent a new window while this app was in the background. The
    /// alarm already scheduled stays until the app is opened and the new one
    /// can be scheduled.
    @Published private(set) var pendingChange = false

    /// Lets her skip the alarm from the wrist without changing the phone's plan.
    @Published var enabledOnWatch: Bool = UserDefaults.standard.object(forKey: "smartAlarm.enabledOnWatch") as? Bool ?? true {
        didSet {
            guard enabledOnWatch != oldValue else { return }
            defaults.set(enabledOnWatch, forKey: Keys.enabledOnWatch)
            reschedule()
            reportStatus()
        }
    }

    /// The last alarm state the phone heard about, so it isn't resent.
    private var reported: (end: Date?, off: Bool)?

    /// Tells the phone which window is armed (nil: none) and whether the
    /// alarm is off on this Watch, so it can remind her to open this app
    /// when tomorrow's alarm still needs arming.
    func reportStatus(force: Bool = false) {
        let end: Date?
        switch status {
        case .scheduled, .listening, .ringing: end = window?.end
        default: end = nil
        }
        let off = !enabledOnWatch
        if !force, let r = reported, r.end == end, r.off == off { return }
        if WatchSync.shared.send(.alarmArmed(end: end, offOnWatch: off)) {
            reported = (end, off)
        }
    }

    var isRinging: Bool {
        if case .ringing = status { return true }
        return false
    }

    private var isListening: Bool {
        if case .listening = status { return true }
        return false
    }

    // Tunables.
    /// A smart-alarm session runs for at most 30 minutes. Keep the last few for
    /// ringing, so the haptics have time to repeat before watchOS ends it.
    private static let ringReserve: TimeInterval = 5 * 60
    private static let maxSessionLength: TimeInterval = 30 * 60
    /// watchOS schedules smart-alarm sessions at most 36 hours ahead.
    private static let maxScheduleAhead: TimeInterval = 36 * 3600
    private static let hapticRepeatInterval: TimeInterval = 2

    private enum Keys {
        static let enabledOnWatch = "smartAlarm.enabledOnWatch"
        static let windowStart = "smartAlarm.windowStart"
        static let windowEnd = "smartAlarm.windowEnd"
        static let completedWindowEnd = "smartAlarm.completedWindowEnd"
    }

    private let defaults = UserDefaults.standard
    private var snapshot: WatchSnapshot = .empty
    private var session: WKExtendedRuntimeSession?
    private var window: AlarmWindow?
    /// The window that was scheduled before the latest change, restored if
    /// watchOS refuses the new one.
    private var fallbackWindow: AlarmWindow?
    private var deadlineTask: Task<Void, Never>?
    private let motion = MotionSleepDetector()
    private let heart = HeartRateRiseDetector()
    private let stopFlag = HapticStopFlag()
    private var rangFromLightSleep = false
    private var wokeSent = false
    /// watchOS only schedules smart-alarm sessions from an active app.
    private var scheduledWhileInactive = false

    // MARK: Scheduling

    /// Call with every new snapshot, and whenever the app becomes active.
    func update(with snapshot: WatchSnapshot) {
        self.snapshot = snapshot
        reschedule()
    }

    /// A session watchOS launched us for (see `WatchAppDelegate`).
    func adopt(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        session = extendedRuntimeSession
        extendedRuntimeSession.delegate = self
        if window == nil { window = persistedWindow() }
        if extendedRuntimeSession.state == .running { beginListening() }
    }

    private func reschedule() {
        let wanted = desiredWindow(now: Date())

        // Never disturb a running session, except to turn the alarm off.
        if let current = session, current.state == .running {
            if wanted == nil && !isRinging {
                cancelSession()
                status = .off
            }
            return
        }

        guard let wanted else {
            cancelSession()
            status = (snapshot.alarmEnabled && enabledOnWatch) ? .noWindow : .off
            return
        }

        // Already scheduled for this window.
        if let current = session, current.state == .scheduled, window == wanted {
            pendingChange = false
            return
        }

        let now = Date()
        if Self.listeningStart(of: wanted).timeIntervalSince(now) > Self.maxScheduleAhead {
            // Too far ahead to schedule (e.g. Friday night with weekends off).
            cancelSession()
            pendingChange = false
            status = .later(start: Self.listeningStart(of: wanted), end: wanted.end)
            return
        }

        // watchOS only schedules from an active app. In the background, keep
        // a good scheduled alarm rather than cancel it for one that would fail.
        if WKApplication.shared().applicationState != .active,
           let current = session, current.state == .scheduled, let old = window, old.end > now {
            pendingChange = true
            return
        }

        let previous: AlarmWindow? = session?.state == .scheduled ? window : nil
        cancelSession()
        fallbackWindow = previous
        schedule(wanted)
    }

    /// When the Watch starts listening for light sleep: the last 25 minutes
    /// before the window's end (a session lasts 30 minutes and keeps 5 for
    /// ringing), or the window's start if it's shorter. So the end really is
    /// the latest it rings.
    nonisolated static func listeningStart(of w: AlarmWindow) -> Date {
        // maxSessionLength − ringReserve, written out so this needs no actor.
        max(w.start, w.end.addingTimeInterval(-25 * 60))
    }

    /// The next occurrence of the phone's window, or nil when the alarm is off.
    private func desiredWindow(now: Date) -> AlarmWindow? {
        guard snapshot.alarmEnabled, enabledOnWatch,
              let start = snapshot.alarmWindowStart, let end = snapshot.alarmWindowEnd,
              end > start, end.timeIntervalSince(start) <= 3 * 3600 else { return nil }
        let completed = (defaults.object(forKey: Keys.completedWindowEnd) as? Double).map { Date(timeIntervalSinceReferenceDate: $0) }
        return Self.nextOccurrence(of: AlarmWindow(start: start, end: end), after: now, skippingEnd: completed,
                                   weekdaysOnly: snapshot.alarmWeekdaysOnly ?? false, oneOff: snapshot.alarmOneOff ?? false)
    }

    /// The phone sends the window for "tomorrow". Move it to the next time that
    /// clock window comes round: back a day if it's after midnight and the
    /// earlier morning is still ahead, forward a day for each morning that has
    /// passed (the plan repeats until the phone sends a new one), past a
    /// morning she has already been woken for, and past Saturday and Sunday
    /// with `weekdaysOnly`. A one-off window (exam mode) is only ever that
    /// morning. May be more than 36 hours ahead; the caller checks.
    static func nextOccurrence(of window: AlarmWindow, after now: Date, skippingEnd completed: Date?,
                               weekdaysOnly: Bool = false, oneOff: Bool = false,
                               calendar: Calendar = .current) -> AlarmWindow? {
        func shifted(_ w: AlarmWindow, days: Int) -> AlarmWindow? {
            guard let s = calendar.date(byAdding: .day, value: days, to: w.start),
                  let e = calendar.date(byAdding: .day, value: days, to: w.end) else { return nil }
            return AlarmWindow(start: s, end: e)
        }
        func isDone(_ w: AlarmWindow) -> Bool {
            if w.end <= now { return true }
            if let completed, abs(w.end.timeIntervalSince(completed)) < 60 { return true }
            return false
        }
        if oneOff { return isDone(window) ? nil : window }
        func skipped(_ w: AlarmWindow) -> Bool { isDone(w) || (weekdaysOnly && calendar.isDateInWeekend(w.end)) }
        var w = window
        for _ in 0..<7 {
            guard let earlier = shifted(w, days: -1), !isDone(earlier) else { break }
            w = earlier
        }
        for _ in 0..<9 {
            guard skipped(w) else { break }
            guard let later = shifted(w, days: 1) else { return nil }
            w = later
        }
        guard !skipped(w) else { return nil }
        return w
    }

    private func schedule(_ w: AlarmWindow) {
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        session = newSession
        window = w
        wokeSent = false
        pendingChange = false
        persist(w)
        scheduledWhileInactive = WKApplication.shared().applicationState != .active
        let listenFrom = Self.listeningStart(of: w)
        status = .scheduled(start: listenFrom, end: w.end)
        if listenFrom <= Date() {
            // Already inside the window (e.g. she opened the app late).
            newSession.start()
        } else {
            newSession.start(at: listenFrom)
        }
    }

    private func cancelSession() {
        stopSensors()
        if let old = session {
            session = nil
            if old.state != .invalid { old.invalidate() }
        }
    }

    // MARK: Listening

    private func beginListening() {
        guard let session, session.state == .running, !isListening, !isRinging else { return }
        let now = Date()
        let w = window ?? AlarmWindow(start: now, end: now.addingTimeInterval(Self.maxSessionLength - Self.ringReserve))
        let expiry = session.expirationDate ?? now.addingTimeInterval(Self.maxSessionLength)
        // Ring by the end of the window, but early enough that watchOS doesn't
        // end the session mid-alarm. Ringing early stays inside the window.
        let deadline = min(w.end, expiry.addingTimeInterval(-Self.ringReserve))

        stopFlag.set(false)
        status = .listening(end: deadline)
        motion.onLightSleep = { [weak self] in
            Task { @MainActor in self?.lightSleepDetected() }
        }
        heart.onRise = { [weak self] in
            Task { @MainActor in self?.lightSleepDetected() }
        }
        motion.start()
        heart.start(windowStart: now)

        deadlineTask?.cancel()
        let wait = max(deadline.timeIntervalSince(now), 0)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.ring(fromLightSleep: false)
        }
    }

    private func lightSleepDetected() {
        guard isListening else { return }
        ring(fromLightSleep: true)
    }

    private func stopSensors() {
        deadlineTask?.cancel()
        deadlineTask = nil
        motion.stop()
        heart.stop()
    }

    // MARK: Ringing

    private func ring(fromLightSleep: Bool) {
        guard let session, session.state == .running, !isRinging else { return }
        stopSensors()
        rangFromLightSleep = fromLightSleep
        stopFlag.set(false)
        status = .ringing(fromLightSleep: fromLightSleep)
        let flag = stopFlag
        let interval = Self.hapticRepeatInterval
        session.notifyUser(hapticType: .notification) { nextHaptic in
            // Returning 0 stops the repeats.
            if flag.isSet { return 0 }
            nextHaptic.pointee = .notification
            return interval
        }
    }

    /// The Stop button.
    func stop() {
        guard isRinging else { return }
        stopFlag.set(true)
        sendWoke(at: Date())
        markCompleted()
        let finished = session
        session = nil
        finished?.invalidate()
        let wokeAt = Date()
        // Line up tomorrow's alarm while the app is active.
        reschedule()
        if case .scheduled = status { return }
        if case .later = status { return }
        status = .woke(at: wokeAt)
    }

    private func sendWoke(at date: Date) {
        guard !wokeSent else { return }
        wokeSent = true
        WatchSync.shared.send(.woke(at: date, fromLightSleep: rangFromLightSleep))
    }

    private func markCompleted() {
        if let end = window?.end {
            defaults.set(end.timeIntervalSinceReferenceDate, forKey: Keys.completedWindowEnd)
        }
    }

    // MARK: Session events (called on the main actor from the delegate)

    private func sessionDidStart(_ started: WKExtendedRuntimeSession) {
        if session == nil { adopt(started); return }
        guard started === session else { return }
        fallbackWindow = nil
        beginListening()
    }

    private func sessionWillExpire(_ expiring: WKExtendedRuntimeSession) {
        guard expiring === session else { return }
        // Last chance: ring now rather than miss the morning.
        if isListening { ring(fromLightSleep: false) }
    }

    private func sessionDidInvalidate(_ invalidated: WKExtendedRuntimeSession,
                                      reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        // Ignore sessions we replaced or stopped ourselves.
        guard invalidated === session else { return }
        let wasRinging = isRinging
        let wasListening = isListening
        stopSensors()
        session = nil

        if wasRinging {
            // watchOS ended the session before she tapped Stop. Line up the
            // next alarm now (it only works if the app is active; otherwise
            // the status says to open it).
            sendWoke(at: Date())
            markCompleted()
            let wokeAt = Date()
            reschedule()
            if case .scheduled = status { return }
            if case .later = status { return }
            status = .woke(at: wokeAt)
        } else if wasListening {
            markCompleted()
            reschedule()
            if case .scheduled = status { return }
            status = .failed("watchOS ended the alarm early. Use a backup alarm tonight.")
        } else if reason == .sessionInProgress {
            // A session from before the app was relaunched is still set.
            status = .failed("An earlier alarm is still set on this Watch.")
        } else if let error {
            // Couldn't schedule. Put back the alarm that was set before, if
            // there was one; otherwise, if the app wasn't active, try again
            // when it next comes forward (see HealthDashboardWatchApp).
            let failed = window
            if let previous = fallbackWindow, previous != failed, previous.end > Date(),
               WKApplication.shared().applicationState == .active {
                fallbackWindow = nil
                schedule(previous)
                pendingChange = true
                return
            }
            fallbackWindow = nil
            status = scheduledWhileInactive ? .needsForeground : .failed(error.localizedDescription)
        } else {
            status = .off
        }
    }

    // MARK: Persistence (survives a relaunch for the scheduled session)

    private func persist(_ w: AlarmWindow) {
        defaults.set(w.start.timeIntervalSinceReferenceDate, forKey: Keys.windowStart)
        defaults.set(w.end.timeIntervalSinceReferenceDate, forKey: Keys.windowEnd)
    }

    private func persistedWindow() -> AlarmWindow? {
        guard let s = defaults.object(forKey: Keys.windowStart) as? Double,
              let e = defaults.object(forKey: Keys.windowEnd) as? Double else { return nil }
        return AlarmWindow(start: Date(timeIntervalSinceReferenceDate: s), end: Date(timeIntervalSinceReferenceDate: e))
    }
}

extension SmartAlarmManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in self.sessionDidStart(extendedRuntimeSession) }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in self.sessionWillExpire(extendedRuntimeSession) }
    }

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        Task { @MainActor in self.sessionDidInvalidate(extendedRuntimeSession, reason: reason, error: error) }
    }
}

/// Read by the haptic repeat handler, which WatchKit may call off the main thread.
private final class HapticStopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    func set(_ value: Bool) {
        lock.lock(); stopped = value; lock.unlock()
    }
}

// MARK: - Movement

/// Light sleep shows up as small movements; deep sleep is almost still.
/// Sums how much the accelerometer magnitude changes in 10-second slices and
/// flags light sleep when, within a rolling 2-minute window, at least two
/// slices move clearly more than her baseline for the night.
final class MotionSleepDetector: @unchecked Sendable {
    /// Called once per run, on a background queue.
    var onLightSleep: (@Sendable () -> Void)?

    private static let sampleInterval: TimeInterval = 0.1   // 10 Hz
    private static let sliceLength: TimeInterval = 10
    private static let windowSlices = 12                     // 2 minutes
    private static let activeSlicesNeeded = 2
    private static let baselineFactor = 3.0
    /// Minimum extra movement over baseline (sum of |change in g| per slice).
    private static let minimumExtra = 0.25

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "SmartAlarm.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    // Only touched on `queue`.
    private var lastMagnitude: Double?
    private var sliceStart: TimeInterval?
    private var sliceSum = 0.0
    private var slices: [Double] = []
    private var fired = false

    func start() {
        guard manager.isAccelerometerAvailable, !manager.isAccelerometerActive else { return }
        queue.addOperation { [self] in
            lastMagnitude = nil; sliceStart = nil; sliceSum = 0; slices = []; fired = false
        }
        manager.accelerometerUpdateInterval = Self.sampleInterval
        manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.add(data.acceleration, at: data.timestamp)
        }
    }

    func stop() {
        if manager.isAccelerometerActive { manager.stopAccelerometerUpdates() }
    }

    private func add(_ a: CMAcceleration, at time: TimeInterval) {
        let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        if let last = lastMagnitude { sliceSum += abs(magnitude - last) }
        lastMagnitude = magnitude

        guard let start = sliceStart else { sliceStart = time; return }
        guard time - start >= Self.sliceLength else { return }
        slices.append(sliceSum)
        sliceSum = 0
        sliceStart = time
        evaluate()
    }

    private func evaluate() {
        guard !fired, slices.count >= Self.windowSlices, let baseline = slices.median else { return }
        let threshold = max(baseline * Self.baselineFactor, baseline + Self.minimumExtra)
        let recent = slices.suffix(Self.windowSlices)
        let active = recent.filter { $0 > threshold }.count
        if active >= Self.activeSlicesNeeded {
            fired = true
            onLightSleep?()
        }
    }
}

// MARK: - Heart rate

/// Heart rate rises a little as sleep lightens toward waking. Averages the
/// readings in the window's first 5 minutes and flags light sleep when a later
/// reading is at least 4 bpm higher.
final class HeartRateRiseDetector: @unchecked Sendable {
    /// Called once per run, on a HealthKit queue.
    var onRise: (@Sendable () -> Void)?

    private static let baselinePeriod: TimeInterval = 5 * 60
    /// Readings from just before the window, used only if the Watch took none
    /// in the first 5 minutes (it samples sparsely during sleep).
    private static let lookBack: TimeInterval = 10 * 60
    private static let riseNeeded = 4.0

    private let store = HKHealthStore()
    private let lock = NSLock()
    private var query: HKAnchoredObjectQuery?
    private var windowStart = Date()
    private var readings: [(date: Date, bpm: Double)] = []
    private var fired = false

    func start(windowStart: Date) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        stop()
        lock.lock()
        self.windowStart = windowStart
        readings = []
        fired = false
        lock.unlock()

        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart.addingTimeInterval(-Self.lookBack), end: nil)
        let q = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil,
                                      limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            self?.add(samples ?? [])
        }
        q.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.add(samples ?? [])
        }
        lock.lock(); query = q; lock.unlock()
        store.execute(q)
    }

    func stop() {
        lock.lock()
        let q = query
        query = nil
        lock.unlock()
        if let q { store.stop(q) }
    }

    private func add(_ samples: [HKSample]) {
        let quantities = samples.compactMap { $0 as? HKQuantitySample }
        guard !quantities.isEmpty else { return }
        lock.lock()
        for s in quantities {
            readings.append((date: s.startDate, bpm: s.quantity.doubleValue(for: .bpm)))
        }
        let shouldFire = !fired && hasRisen()
        if shouldFire { fired = true }
        lock.unlock()
        if shouldFire { onRise?() }
    }

    /// Call with `lock` held.
    private func hasRisen() -> Bool {
        let baselineEnd = windowStart.addingTimeInterval(Self.baselinePeriod)
        let firstMinutes = readings.filter { $0.date >= windowStart && $0.date < baselineEnd }.map { $0.bpm }
        let before = readings.filter { $0.date < windowStart }.map { $0.bpm }
        guard let baseline = firstMinutes.mean ?? before.mean else { return false }
        return readings.contains { $0.date >= baselineEnd && $0.bpm >= baseline + Self.riseNeeded }
    }
}

// MARK: - Ringing screen

/// Full screen while the alarm rings, with one big Stop button.
struct AlarmView: View {
    @EnvironmentObject private var alarm: SmartAlarmManager

    private var fromLightSleep: Bool {
        if case let .ringing(fromLightSleep) = alarm.status { return fromLightSleep }
        return false
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Accent.orange.ink(.dark))
                .accessibilityHidden(true)
            TimelineView(.everyMinute) { context in
                Text(Clock.format(Clock.minutesOfDay(context.date)))
                    .font(.number(40))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            Text(fromLightSleep ? "You were stirring. Good time to get up." : "End of your wake window.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0xE6D2BC))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                alarm.stop()
            } label: {
                Text("Stop")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Capsule().fill(Accent.orange.fill(.dark)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop alarm")
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Color(hex: 0x7A3A00), Color(hex: 0x331700), .black],
                           center: UnitPoint(x: 0.8, y: 0), startRadius: 0, endRadius: 220)
                .ignoresSafeArea()
        )
    }
}
