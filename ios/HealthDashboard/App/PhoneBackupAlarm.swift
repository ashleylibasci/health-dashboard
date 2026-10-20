import AlarmKit
import SwiftUI

/// A regular iPhone alarm at the smart alarm's latest time, for mornings the Watch can't wake her
/// (not worn, flat, or never got the alarm set). It rings like the Clock app, even on silent.
/// When the Watch wakes her first it tells the phone, which cancels this one.
@MainActor
enum PhoneBackupAlarm {
    private static let idKey = "phoneBackupAlarmID"
    private static let dateKey = "phoneBackupAlarmDate"

    /// AlarmKit's simple alert needs iOS 26.1.
    static var isAvailable: Bool {
        if #available(iOS 26.1, *) { return true }
        return false
    }

    /// When the backup is set for, if it is.
    static var scheduledFor: Date? { (UserDefaults.standard.object(forKey: dateKey) as? Date).flatMap { $0 > .now ? $0 : nil } }

    /// Puts the backup at the plan's next latest time (or the time the Watch confirmed), or
    /// removes it when there's no plan or she doesn't want one.
    static func update(for plan: SmartAlarmPlan?, latest: Date? = nil) async {
        guard #available(iOS 26.1, *) else { return }
        guard let plan, plan.phoneBackup else { cancel(); return }
        let when = latest ?? plan.nextLatest(after: .now)
        if scheduledFor == when { return }
        cancel()
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined { _ = try? await manager.requestAuthorization() }
        guard manager.authorizationState == .authorized else { return }
        let id = UUID()
        let attributes = AlarmAttributes<BackupAlarmMetadata>(
            presentation: AlarmPresentation(alert: .init(title: "Time to get up")),
            tintColor: Color(hex: 0xE0A800))
        do {
            _ = try await manager.schedule(id: id, configuration: .alarm(schedule: .fixed(when), attributes: attributes))
            UserDefaults.standard.set(id.uuidString, forKey: idKey)
            UserDefaults.standard.set(when, forKey: dateKey)
        } catch {
            // Not allowed or not possible: the Watch alarm still stands on its own.
        }
    }

    static func cancel() {
        if #available(iOS 26.1, *), let s = UserDefaults.standard.string(forKey: idKey), let id = UUID(uuidString: s) {
            try? AlarmManager.shared.cancel(id: id)
        }
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
    }
}

@available(iOS 26.0, *)
struct BackupAlarmMetadata: AlarmMetadata {}
