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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
