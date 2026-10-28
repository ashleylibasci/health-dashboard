import AlarmKit
import SwiftUI
import UIKit

/// A regular iPhone alarm at the smart alarm's latest time, for mornings the
/// Watch can't wake her (not worn, flat, or the Watch alarm never turned on). It
/// rings like the Clock app, even on silent. When she stops the Watch's
/// alarm, the Watch tells the phone, which cancels this one.
///
/// Updates run one after another, and each clears every alarm this app has
/// scheduled except the one it keeps, so there's never a second, forgotten
/// alarm. AlarmKit's simple alert needs iOS 26.1; earlier iOS has no backup
/// (the setting says so).
@MainActor
final class PhoneBackupAlarm: ObservableObject {
    static let shared = PhoneBackupAlarm()

    /// When the backup is set for, if it is.
    @Published private(set) var scheduledFor: Date? {
        didSet { UserDefaults.standard.set(scheduledFor, forKey: Self.dateKey) }
    }
    /// She said no to alarms for this app in iOS Settings.
    @Published private(set) var denied = false

    /// Not the older app's "phoneBackupAlarmDate": this app replaced it, and
    /// must not adopt (and then cancel) an alarm it didn't set.
    private static let dateKey = "next.phoneBackupAlarmDate"
    private var queue: Task<Void, Never>?

    private init() {
        scheduledFor = (UserDefaults.standard.object(forKey: Self.dateKey) as? Date).flatMap { $0 > .now ? $0 : nil }
        if #available(iOS 26.1, *) { denied = AlarmManager.shared.authorizationState == .denied }
    }

    static var isAvailable: Bool {
        if #available(iOS 26.1, *) { return true }
        return false
    }

    /// Asks iOS while she's looking (when she turns the backup on), so the
    /// request never comes up from the background where it can't show.
    func requestPermission() async {
        guard #available(iOS 26.1, *) else { return }
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined { _ = try? await manager.requestAuthorization() }
        denied = manager.authorizationState == .denied
    }

    /// Puts the backup at `date` (the smart alarm's latest time), or removes
    /// it when nil. Queued behind any earlier update.
    func update(at date: Date?) {
        let wanted = date.flatMap { $0 > .now ? $0 : nil }
        let previous = queue
        queue = Task {
            await previous?.value
            await apply(wanted)
        }
    }

    /// The Watch woke her and she stopped it at `stoppedAt`. Cancel the backup
    /// only if it's this morning's (a message delayed until the next day
    /// mustn't cancel that one).
    func watchRang(at stoppedAt: Date) {
        guard let at = scheduledFor, at.timeIntervalSince(stoppedAt) > -10 * 60, at.timeIntervalSince(stoppedAt) < 60 * 60 else { return }
        update(at: nil)
    }

    private func apply(_ wanted: Date?) async {
        guard #available(iOS 26.1, *) else { return }
        let manager = AlarmManager.shared
        let existing = (try? manager.alarms) ?? []
        if let wanted, wanted == scheduledFor, existing.count == 1 { return }
        // Nothing wanted and nothing of ours set: leave any alarm alone. The
        // older app this one replaced may have left tomorrow's backup, and
        // it should still ring until she turns this app's backup on.
        if wanted == nil, scheduledFor == nil { return }
        // Clear everything this app scheduled; only the alarm made below stays.
        for alarm in existing { try? manager.cancel(id: alarm.id) }
        scheduledFor = nil
        guard let wanted else { return }
        if manager.authorizationState == .notDetermined, UIApplication.shared.applicationState == .active {
            _ = try? await manager.requestAuthorization()
        }
        denied = manager.authorizationState == .denied
        guard manager.authorizationState == .authorized else { return }
        let attributes = AlarmAttributes<BackupAlarmMetadata>(
            presentation: AlarmPresentation(alert: .init(title: "Time to get up")),
            tintColor: Accent.purple.fill(.dark))
        do {
            _ = try await manager.schedule(id: UUID(), configuration: .alarm(schedule: .fixed(wanted), attributes: attributes))
            scheduledFor = wanted
        } catch {
            // Not possible right now: the Watch alarm still stands on its own.
        }
    }
}

@available(iOS 26.0, *)
struct BackupAlarmMetadata: AlarmMetadata {}
