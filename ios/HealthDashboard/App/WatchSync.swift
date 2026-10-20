import Foundation
import WatchConnectivity

/// Sends today's summary to the Watch app. The Watch keeps the latest one, so it has
/// numbers to show even when the phone isn't nearby.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled, let data = snapshot.encoded else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
        // Complication updates get a small daily budget (about 50), so send at most every 30 minutes.
        if WCSession.default.isComplicationEnabled, WCSession.default.remainingComplicationUserInfoTransfers > 0,
           Date.now.timeIntervalSince(lastComplicationSend) > 1800 {
            lastComplicationSend = .now
            WCSession.default.transferCurrentComplicationUserInfo(["snapshot": data])
        }
    }

    private var lastComplicationSend = Date.distantPast

    /// Whether there's a Watch with the app on it to send the alarm to.
    var watchReady: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    /// The smart alarm plan (nil turns it off): straight to the Watch app if it's open, else queued for
    /// when it is. Before the connection is up (Siri can run this right after launch) it's held and
    /// sent once it is, so a "turn off" is never dropped.
    func sendAlarm(_ plan: SmartAlarmPlan?) {
        let message: [String: Any] = plan.flatMap { try? JSONEncoder().encode($0) }.map { ["alarmPlan": $0] } ?? ["alarmOff": true]
        guard watchReady else {
            pendingAlarm = message
            return
        }
        pendingAlarm = nil
        deliver(message)
    }

    private var pendingAlarm: [String: Any]?

    func requestAlarmStatus() {
        guard watchReady, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["alarmStatusRequest": true], replyHandler: nil)
    }

    private func deliver(_ message: [String: Any]) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in WCSession.default.transferUserInfo(message) }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { receive(userInfo) }

    private func receive(_ message: [String: Any]) {
        if let stoppedAt = message["alarmRang"] as? Date {
            Task { @MainActor in AlarmLink.shared.watchRang(at: stoppedAt) }
        }
        guard let data = message["alarmStatus"] as? Data,
              let status = try? JSONDecoder().decode(WatchAlarmStatus.self, from: data) else { return }
        Task { @MainActor in AlarmLink.shared.receive(status) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        if let pendingAlarm, watchReady {
            self.pendingAlarm = nil
            deliver(pendingAlarm)
        }
        Task { @MainActor in AlarmLink.shared.refresh() }
    }

    /// The Watch app was just installed: send it anything waiting.
    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in AlarmLink.shared.refresh() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
