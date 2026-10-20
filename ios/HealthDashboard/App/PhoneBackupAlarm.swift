import AlarmKit
import Observation
import SwiftUI
import UIKit

/// A regular iPhone alarm at the smart alarm's latest time, for mornings the Watch can't wake her
/// (not worn, flat, or never got the alarm set). It rings like the Clock app, even on silent.
/// Once she stops the Watch's alarm, the Watch tells the phone, which cancels this one.
///
/// Updates run one after another, and each one clears every alarm this app has scheduled except
/// the one it keeps, so there's never a second, forgotten alarm.
@MainActor
@Observable
final class PhoneBackupAlarm {
    static let shared = PhoneBackupAlarm()

    /// When the backup is set for, if it is.
    private(set) var scheduledFor: Date? {
        didSet { UserDefaults.standard.set(scheduledFor, forKey: Self.dateKey) }
    }
    /// She said no to alarms in iOS, so the backup can't be set.
    private(set) var denied = false

    private static let idKey = "phoneBackupAlarmID"
    private static let dateKey = "phoneBackupAlarmDate"
    private var queue: Task<Void, Never>?

    init() {
        scheduledFor = (UserDefaults.standard.object(forKey: Self.dateKey) as? Date).flatMap { $0 > .now ? $0 : nil }
        if #available(iOS 26.1, *) { denied = AlarmManager.shared.authorizationState == .denied }
    }

    /// AlarmKit's simple alert needs iOS 26.1.
    static var isAvailable: Bool {
        if #available(iOS 26.1, *) { return true }
        return false
    }

    /// Asks iOS for permission while she's looking (when she turns the backup on), so the request
    /// never comes up later from the background where it can't be shown.
    func requestPermission() async {
        guard #available(iOS 26.1, *) else { return }
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined { _ = try? await manager.requestAuthorization() }
        denied = manager.authorizationState == .denied
    }

    /// Puts the backup at the plan's next latest time (or the time the Watch confirmed), or
    /// removes it when there's no plan or she doesn't want one. Queued behind any earlier update.
    func update(for plan: SmartAlarmPlan?, latest: Date? = nil) {
        let previous = queue
        queue = Task {
            await previous?.value
            await apply(plan: plan, latest: latest.flatMap { $0 > .now ? $0 : nil })
        }
    }

    /// Waits for queued updates, for callers like Siri that must finish before returning.
    func settle() async { await queue?.value }

    /// The Watch woke her and she stopped it at `stoppedAt`. Cancel the backup only if it's this
    /// morning's (a message delayed until the next day mustn't cancel that one).
    func watchRang(at stoppedAt: Date) {
        guard let at = scheduledFor, at.timeIntervalSince(stoppedAt) > -10 * 60, at.timeIntervalSince(stoppedAt) < 60 * 60 else { return }
        update(for: nil)
    }

    private func apply(plan: SmartAlarmPlan?, latest: Date?) async {
        guard #available(iOS 26.1, *) else { return }
        let manager = AlarmManager.shared
        let wanted = plan.flatMap { $0.phoneBackup ? (latest ?? $0.nextLatest(after: .now)) : nil }
        let existing = (try? manager.alarms) ?? []
        if let wanted, wanted == scheduledFor, existing.count == 1 { return }
        // Clear everything this app scheduled; only the alarm made below is kept.
        for alarm in existing { try? manager.cancel(id: alarm.id) }
        UserDefaults.standard.removeObject(forKey: Self.idKey)
        scheduledFor = nil
        guard let wanted else { return }
        if manager.authorizationState == .notDetermined, UIApplication.shared.applicationState == .active {
            _ = try? await manager.requestAuthorization()
        }
        denied = manager.authorizationState == .denied
        guard manager.authorizationState == .authorized else { return }
        let id = UUID()
        let attributes = AlarmAttributes<BackupAlarmMetadata>(
            presentation: AlarmPresentation(alert: .init(title: "Time to get up")),
            tintColor: Color(hex: 0xE0A800))
        do {
            _ = try await manager.schedule(id: id, configuration: .alarm(schedule: .fixed(wanted), attributes: attributes))
            UserDefaults.standard.set(id.uuidString, forKey: Self.idKey)
            scheduledFor = wanted
        } catch {
            // Not possible right now: the Watch alarm still stands on its own.
        }
    }
}

@available(iOS 26.0, *)
struct BackupAlarmMetadata: AlarmMetadata {}
