import Foundation
import Observation

/// The smart alarm as the iPhone sees it: the plan set here, and what the Watch last said about it.
/// The Watch does the waking; watchOS only lets it schedule the alarm while its app is open, so
/// a plan sent from here can wait on the Watch until she next opens the app there.
@MainActor
@Observable
final class AlarmLink {
    static let shared = AlarmLink()

    private(set) var plan: SmartAlarmPlan? { didSet { save(plan, "phoneAlarmPlan") } }
    private(set) var watchStatus: WatchAlarmStatus? { didSet { save(watchStatus, "phoneAlarmStatus") } }

    init() {
        let d = UserDefaults.standard
        plan = d.data(forKey: "phoneAlarmPlan").flatMap { try? JSONDecoder().decode(SmartAlarmPlan.self, from: $0) }
        watchStatus = d.data(forKey: "phoneAlarmStatus").flatMap { try? JSONDecoder().decode(WatchAlarmStatus.self, from: $0) }
    }

    /// Sets (or, with nil, turns off) the alarm and sends it to the Watch.
    func set(_ plan: SmartAlarmPlan?) {
        self.plan = plan
        watchStatus = nil
        WatchSync.shared.sendAlarm(plan)
        Task { await PhoneBackupAlarm.update(for: plan) }
    }

    /// The Watch's report. Its plan wins, so a change made on the Watch shows here too.
    func receive(_ status: WatchAlarmStatus) {
        watchStatus = status
        if status.state == .off { plan = nil } else if let p = status.plan { plan = p }
        // The backup follows the Watch: at the time it confirmed, or the plan's next time while it waits.
        Task { await PhoneBackupAlarm.update(for: plan, latest: status.state == .armed ? status.latest : nil) }
    }

    /// The Watch woke her: this morning's backup on the iPhone isn't needed.
    func watchRang() {
        guard let at = PhoneBackupAlarm.scheduledFor, at.timeIntervalSinceNow < 3 * 3600 else { return }
        PhoneBackupAlarm.cancel()
    }

    /// Asks the Watch how things stand, and resends a plan the Watch never got (it wasn't
    /// reachable or set up when she saved it).
    func refresh() {
        if let plan, watchStatus == nil { WatchSync.shared.sendAlarm(plan) }
        WatchSync.shared.requestAlarmStatus()
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        UserDefaults.standard.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}
