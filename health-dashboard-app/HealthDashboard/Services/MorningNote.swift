import Foundation
import UserNotifications
import HealthCore

/// One morning note (D-N1), about 45 minutes after she wakes: "68 · Take it
/// steady" on top, "Pill day 18 · bed by 11:50pm tonight" underneath, with
/// Log latte and +1 bottle buttons that log without opening the app.
///
/// When Apple Health hands the app last night's sleep, the note is set for
/// 45 minutes after she woke (or a minute from now if that's passed, up to
/// 3 hours after waking). The evening before, a stand-in is set for her
/// usual morning in case the app doesn't get woken: it has the pill day
/// and bedtime but no score. Either way, at most one a day.
///
/// The pill is private on the lock screen (H-A5): the title never names
/// it, and the body only does when iOS hides bodies until the phone is
/// unlocked.
enum MorningNote {
    static let prefix = "morning-note-"
    static let category = "morningNote"
    static let latteAction = "morning.latte"
    static let bottleAction = "morning.bottle"
    /// When each recent morning's note was set to go out (day → fire time).
    private static let firesKey = "morningNote.fires"

    struct Note: Hashable {
        /// Midnight of the morning it's for.
        var day: Date
        var fire: Date
        var title: String
        var body: String
    }

    private static func key(_ day: Date) -> String { day.formatted(.iso8601.year().month().day()) }

    private static var fires: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: firesKey) as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: firesKey) }
    }

    /// The note for `day` went out already (its time has passed).
    static func alreadySent(for day: Date, now: Date = .now) -> Bool {
        fires[key(day)].map { $0 <= now } ?? false
    }

    /// Sets (or replaces) the note for its morning. Does nothing more if
    /// notifications aren't allowed.
    static func schedule(_ note: Note, latteName: String?) async {
        guard await Nudges.isAllowed() else { return }
        await registerCategory(latteName: latteName)
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.categoryIdentifier = category
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: note.fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: prefix + key(note.day), content: content, trigger: trigger))
            // Only the last few mornings matter.
            var all = fires.filter { $0.value > note.fire.addingTimeInterval(-4 * 86_400) }
            all[key(note.day)] = note.fire
            fires = all
        } catch {
            // Not scheduled: the next refresh tries again.
        }
    }

    static func cancel() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// The two buttons. The latte one is named after her quick drink.
    static func registerCategory(latteName: String?) async {
        let center = UNUserNotificationCenter.current()
        let latte = UNNotificationAction(identifier: latteAction, title: "Log \((latteName ?? "latte").lowercased())", options: [],
                                         icon: UNNotificationActionIcon(systemImageName: "cup.and.saucer.fill"))
        let bottle = UNNotificationAction(identifier: bottleAction, title: "+1 bottle", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "drop.fill"))
        let mine = UNNotificationCategory(identifier: category, actions: [latte, bottle], intentIdentifiers: [],
                                          hiddenPreviewsBodyPlaceholder: PrivateNotice.placeholder,
                                          options: [.hiddenPreviewsShowTitle])
        let others = await center.notificationCategories().filter { $0.identifier != category }
        center.setNotificationCategories(others.union([mine]))
    }
}

extension AppModel {
    /// Schedules the morning note (D-N1) from the freshest numbers, or a
    /// stand-in for tomorrow. Only from her own nights; never twice a day.
    func updateMorningNote() async {
        if DemoMode.morningNote, !Self.demoMorningNoteSent, await Nudges.isAllowed() {
            Self.demoMorningNoteSent = true
            let w = MorningNoteText.words(score: recoveryShown, label: recoveryLabel, pillDay: pillToday?.packDay,
                                          bedtime: tonightBedtime, bodyHiddenWhenLocked: await PrivateNotice.bodyHiddenWhenLocked())
            await MorningNote.schedule(.init(day: Calendar.current.startOfDay(for: .now), fire: .now.addingTimeInterval(10),
                                             title: w.title, body: w.body), latteName: WidgetSnapshot.load()?.quickDrink?.name)
            return
        }
        guard store.data.insights.morningNote, !usingSampleData else { await MorningNote.cancel(); return }
        let hidden = await PrivateNotice.bodyHiddenWhenLocked()
        let latte = WidgetSnapshot.load()?.quickDrink?.name
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        if lastNightIsFresh, lastNightIsReal, let wake = lastNight.wakeDate, cal.isDate(wake, inSameDayAs: today),
           !MorningNote.alreadySent(for: today), let fire = MorningNoteText.fireDate(wake: wake) {
            let pill = pillToday.flatMap { $0.isPillDay ? $0.packDay : nil }
            let w = MorningNoteText.words(score: recoveryShown, label: recoveryShown == nil ? nil : recoveryLabel,
                                          pillDay: pill, bedtime: tonightBedtime, bodyHiddenWhenLocked: hidden)
            await MorningNote.schedule(.init(day: today, fire: fire, title: w.title, body: w.body), latteName: latte)
            return
        }
        // The stand-in for tomorrow morning, at her latest up time + 45,
        // replaced if the app gets her sleep in time.
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today), !MorningNote.alreadySent(for: tomorrow) else { return }
        let up = nextAlarmWindow.map { Clock.minutesOfDay($0.end) } ?? store.data.upBy
        let fire = AppDay.date(up + MorningNoteText.lead, relativeTo: tomorrow)
        let pill = pillPack.flatMap { $0.isPillDay(tomorrow) ? $0.day(on: tomorrow) : nil }
        let w = MorningNoteText.words(score: nil, label: nil, pillDay: pill, bedtime: tonightBedtime, bodyHiddenWhenLocked: hidden)
        await MorningNote.schedule(.init(day: tomorrow, fire: fire, title: w.title, body: w.body), latteName: latte)
    }

    /// `-demoMorningNote` already sent this launch.
    @MainActor private static var demoMorningNoteSent = false
}
