import Foundation
import UserNotifications
import HealthCore

/// The refill countdown (H-A6): "Last pack: refill by Nov 20", set once
/// from how many packs she picked up, with a private reminder a week
/// ahead (earlier before Thanksgiving or winter break).
extension AppModel {
    var pillRefill: PillRefill? {
        guard packMethod != nil, let packs = store.data.refillPacks, let from = store.data.refillCountedFrom else { return nil }
        return PillRefill(countedFrom: from, packs: packs, packLength: store.data.packLength)
    }

    /// "I have `n` packs, counting the one I'm on": counted from this
    /// pack's first day.
    func setPacksLeft(_ n: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        store.data.refillCountedFrom = cal.date(byAdding: .day, value: -((packDay ?? 1) - 1), to: today)
        store.data.refillPacks = max(n, 0)
    }

    var packsLeftNow: Int? { pillRefill?.packsLeft(on: .now) }

    /// "Last pack: refill by Nov 20", "3 packs left", "Packs ran out Nov 8".
    var refillTitle: String {
        guard let r = pillRefill, let left = packsLeftNow else { return "Packs left" }
        switch left {
        case 0: return "Packs ran out \(Self.refillDate(r.refillBy()))"
        case 1: return "Last pack: refill by \(Self.refillDate(r.refillBy()))"
        default: return "\(left) packs left"
        }
    }

    var refillNote: String {
        guard let r = pillRefill, let left = packsLeftNow else { return "Set it when you pick up a refill" }
        switch left {
        case 0: return "Picked up more? Update it here"
        case 1: return r.reminder() > .now ? "Reminder on \(Self.refillDate(r.reminder()))" : "Pick up your refill soon"
        default: return "Refill by \(Self.refillDate(r.refillBy())) \u{00B7} reminder a week ahead"
        }
    }

    static func refillDate(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }

    // MARK: Reminder

    private static let refillID = "refill-reminder"

    /// One private notification on the reminder day; none once it's past
    /// or the count isn't set.
    func updateRefillReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.refillID])
        guard let r = pillRefill, r.reminder() > .now, await Nudges.isAllowed() else { return }
        await PillReminders.registerCategory()
        let content = PrivateNotice.content(at: PillRefill.reminderTime)
        content.categoryIdentifier = PrivateNotice.category
        if await PrivateNotice.bodyHiddenWhenLocked() {
            let left = r.packsLeft(on: r.reminder())
            content.body = "\(left <= 1 ? "Last pack" : "\(left) packs left"): refill by \(Self.refillDate(r.refillBy())), before you run out."
        }
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.reminder())
        try? await center.add(UNNotificationRequest(identifier: Self.refillID, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
}
