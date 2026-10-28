import Foundation
import WatchConnectivity

/// What the phone sends the Watch: tonight's smart-alarm window and the
/// glanceable numbers. Sent as an application context, so the Watch always
/// has the latest even if it was asleep when the phone updated.
struct WatchSnapshot: Codable, Equatable {
    var recovery: Int
    var recoveryLabel: String
    var energyNow: Int
    var energyZoneTitle: String
    var nextZoneTitle: String
    var nextZoneStart: Date?
    var bedtime: Date?
    var alarmWindowStart: Date?
    var alarmWindowEnd: Date?
    var alarmEnabled: Bool
    var caffeineTodayMg: Int
    var caffeineCutoff: Date?
    /// The user's saved drinks, for one-tap logging on the Watch.
    var quickDrinks: [QuickDrink]
    /// 0–100 samples for the energy sparkline, one per 30 minutes from wake.
    var energyCurve: [Double]
    /// When the first curve sample is (wake time). Older phone builds omit it.
    var energyCurveStart: Date? = nil
    /// Today's energy zones, for the touch readout on the Watch.
    var energyZones: [Zone]? = nil
    /// `EnergyDay.Zone.Kind` raw values for the current and next zone, so the
    /// Watch colours them by kind rather than by title.
    var energyZoneKind: String? = nil
    var nextZoneKind: String? = nil
    /// When the numbers in this snapshot were last read from Apple Health
    /// (the phone's last refresh), not when it was sent. Older phone builds
    /// omit it.
    var syncedAt: Date? = nil
    /// True while the phone shows example data (fewer than 14 real nights).
    var isSample: Bool? = nil
    /// The smart alarm skips Saturday and Sunday mornings.
    var alarmWeekdaysOnly: Bool? = nil
    /// The window is for that one morning only (exam mode): don't repeat it
    /// on later days, and ring even on a weekend.
    var alarmOneOff: Bool? = nil
    /// True when the phone has no recovery score today (no heart readings and
    /// no recorded night): show "No reading yet", not `recovery`.
    var recoveryMissing: Bool? = nil
    /// True when no sleep was recorded last night: the energy numbers run
    /// from an older wake time.
    var lastNightMissing: Bool? = nil
    /// Ids of today's logged drinks, so the Watch knows which of the drinks
    /// it sent are already counted in `caffeineTodayMg`.
    var todayDrinkIDs: [UUID]? = nil
    /// Her caffeine cutoff for a typical drink falls before she's up (the
    /// pill, ring or patch slow caffeine down): `caffeineCutoff` is nil then.
    var caffeineCutoffBeforeWake: Bool? = nil
    /// Tonight's plan, the same numbers the phone shows (round 3, N3):
    /// the best wake time (end of a sleep cycle; `alarmWindowEnd` is the
    /// latest the alarm rings, a few minutes after it), her up-by time,
    /// tonight's need and the sleep the plan expects. Older phone builds
    /// omit them.
    var plannedWake: Date? = nil
    var upBy: Date? = nil
    var tonightNeedMinutes: Int? = nil
    var plannedAsleepMinutes: Int? = nil
    /// Today's caffeine leaves 25 mg or more at bedtime: the only time the
    /// Watch shows a warning (nil from older phone builds).
    var caffeineTooMuchAtBedtime: Bool? = nil

    struct Zone: Codable, Equatable {
        var title: String
        var start: Date
        var end: Date
        var kind: String? = nil
    }

    struct QuickDrink: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var caffeineMg: Int
    }

    static let empty = WatchSnapshot(recovery: 0, recoveryLabel: "", energyNow: 0, energyZoneTitle: "", nextZoneTitle: "",
                                     nextZoneStart: nil, bedtime: nil, alarmWindowStart: nil, alarmWindowEnd: nil,
                                     alarmEnabled: false, caffeineTodayMg: 0, caffeineCutoff: nil, quickDrinks: [], energyCurve: [])
}

/// Messages the Watch sends back.
enum WatchMessage: Codable {
    /// Older Watch builds: a saved drink's id and the tap time.
    case loggedDrink(id: UUID, at: Date)
    /// A drink logged on the Watch. `entryID` is the log entry's own id, so the
    /// phone can save it to Apple Health once and undo it later.
    case loggedDrinkEntry(entryID: UUID, drinkID: UUID, name: String, mg: Int, at: Date)
    /// Undo on the Watch, a few seconds after logging.
    case undoDrink(entryID: UUID)
    case woke(at: Date, fromLightSleep: Bool)
    /// The Watch's smart alarm state: the end of the window it has armed (nil
    /// when nothing is armed), and whether she switched it off on the Watch.
    /// Lets the phone remind her to open the Watch app when tomorrow's alarm
    /// still needs arming.
    case alarmArmed(end: Date?, offOnWatch: Bool)

    /// "Latte", for an error message about this message.
    var drinkName: String? {
        if case let .loggedDrinkEntry(_, _, name, _, _) = self { return name }
        return nil
    }
}

@MainActor
final class WatchSync: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSync()
    @Published private(set) var snapshot: WatchSnapshot = .empty
    /// Set when a message to the phone couldn't be delivered.
    @Published private(set) var deliveryError: String?
    var onMessage: ((WatchMessage) -> Void)?
    /// Phone side: the Watch asked for a fresh snapshot (it just opened).
    var onSnapshotRequest: (() -> Void)?
    /// Called once the session is activated: the phone pushes its snapshot
    /// then (a push before activation is dropped).
    var onActivated: (() -> Void)?
    private var errorClearTask: Task<Void, Never>?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        var context: [String: Any] = ["snapshot": data]
        // The watch-face complications' numbers ride along.
        if let widget = WidgetSnapshot.savedData { context["widget"] = widget }
        try? WCSession.default.updateApplicationContext(context)
        #if os(iOS)
        sendComplicationUpdate()
        #endif
    }

    #if os(iOS)
    private var lastComplicationUpdate: Date?
    private var lastComplicationData: Data?

    /// Complications on her watch face update without opening the Watch app,
    /// using the daily complication budget sparingly: only when the numbers
    /// changed, and at most every 30 minutes.
    private func sendComplicationUpdate() {
        let session = WCSession.default
        guard session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0,
              let widget = WidgetSnapshot.savedData, widget != lastComplicationData else { return }
        if let last = lastComplicationUpdate, Date().timeIntervalSince(last) < 30 * 60 { return }
        lastComplicationUpdate = .now
        lastComplicationData = widget
        session.transferCurrentComplicationUserInfo(["widget": widget])
    }
    #endif

    /// Queues a message for the phone. Returns false when it couldn't even be
    /// queued; a later delivery failure shows up in `deliveryError`.
    @discardableResult
    func send(_ message: WatchMessage) -> Bool {
        // Background status (the alarm) never shows an error or clears one.
        let quiet: Bool = { if case .alarmArmed = message { return true }; return false }()
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(message) else {
            if !quiet { setDeliveryError("Couldn't reach your iPhone. Log it there instead.") }
            return false
        }
        if !quiet { clearDeliveryError() }
        if quiet && WCSession.default.isReachable {
            // A live message wakes the phone app, so it hears about the alarm
            // before the evening reminder; queue it if that fails.
            WCSession.default.sendMessage(["message": data], replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(["message": data])
            }
            return true
        }
        // transferUserInfo queues reliably even when the phone isn't reachable.
        WCSession.default.transferUserInfo(["message": data])
        return true
    }

    func clearDeliveryError() {
        errorClearTask?.cancel()
        deliveryError = nil
    }

    /// Shows a delivery error for 10 seconds (or until the next snapshot),
    /// so it never hides the cutoff for good.
    private func setDeliveryError(_ message: String) {
        deliveryError = message
        errorClearTask?.cancel()
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            self?.deliveryError = nil
        }
    }

    /// Asks the phone for an up-to-date snapshot. Only works while the phone
    /// is reachable; otherwise the last snapshot stays (marked with its time).
    func requestSnapshot() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "snapshot"], replyHandler: nil, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.receive(context: context)
            guard state == .activated else { return }
            #if os(watchOS)
            // Cold launch: ask for today's numbers as soon as we can.
            self.requestSnapshot()
            #endif
            self.onActivated?()
        }
    }

    #if os(watchOS)
    /// The phone came within reach: ask again if what we have is old.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            let old = self.snapshot.syncedAt.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true
            if old { self.requestSnapshot() }
        }
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.receive(context: context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let widget = userInfo["widget"] as? Data {
            WidgetSnapshot.receive(widget)
            return
        }
        guard let data = userInfo["message"] as? Data, let message = try? JSONDecoder().decode(WatchMessage.self, from: data) else { return }
        Task { @MainActor in self.onMessage?(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message["message"] as? Data, let decoded = try? JSONDecoder().decode(WatchMessage.self, from: data) {
            Task { @MainActor in self.onMessage?(decoded) }
            return
        }
        guard message["request"] as? String == "snapshot" else { return }
        Task { @MainActor in self.onSnapshotRequest?() }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil else { return }
        let data = userInfoTransfer.userInfo["message"] as? Data
        let message = data.flatMap { try? JSONDecoder().decode(WatchMessage.self, from: $0) }
        // A missed alarm status is resent with the next change; not worth an error.
        if case .alarmArmed? = message { return }
        let name = message?.drinkName
        Task { @MainActor in
            self.setDeliveryError(name.map { "\($0) didn't reach your iPhone. Log it there instead." }
                ?? "Something didn't reach your iPhone.")
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif

    private func receive(context: [String: Any]) {
        #if os(watchOS)
        if let widget = context["widget"] as? Data { WidgetSnapshot.receive(widget) }
        #endif
        guard let data = context["snapshot"] as? Data, let s = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        snapshot = s
        clearDeliveryError()
    }
}
