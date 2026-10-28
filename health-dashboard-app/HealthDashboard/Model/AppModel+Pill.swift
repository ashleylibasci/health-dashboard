import Foundation
import HealthCore

/// The combined pill day to day (H-A1): which pill is today's, whether it's
/// taken (tapped here, or logged in Apple Health when she turned that on),
/// the pack's filled-in pills, and the reminders.
extension AppModel {
    // MARK: The pack on the calendar

    /// Combined pill with a known pack day: the pack laid out on the
    /// calendar (from the pack start she set, else from today's estimate).
    var pillPack: PillPack? {
        guard store.birthControl == .combinedPill, let day = packDay else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = store.data.packStartDate.map { cal.startOfDay(for: $0) }
            ?? cal.date(byAdding: .day, value: -(day - 1), to: today) ?? today
        return PillPack(start: start, activeDays: store.data.packActiveDays, packLength: store.data.packLength)
    }

    // MARK: Doses

    /// Every dose: the ones tapped here, and Apple Health's when she turned
    /// that on.
    var pillDoses: [Date] { store.data.pillsTaken + (store.data.pillReadsHealth ? healthPillDoses : []) }

    /// Midnight of the pill day a dose counts for (`PillDay`).
    func pillDay(for dose: Date) -> Date { PillDay.day(for: dose, pillTime: store.data.pillTime) }

    /// The pill day it is now: at 1am, still the evening before's.
    var currentPillDay: Date { pillDay(for: .now) }

    /// The first dose that counts for `day` (midnight), and whether it came
    /// from Apple Health.
    func pillDose(on day: Date) -> (date: Date, fromHealth: Bool)? {
        let cal = Calendar.current
        if let mine = store.data.pillsTaken.filter({ cal.isDate(pillDay(for: $0), inSameDayAs: day) }).min() {
            return (mine, false)
        }
        guard store.data.pillReadsHealth else { return nil }
        return healthPillDoses.filter { cal.isDate(pillDay(for: $0), inSameDayAs: day) }.min().map { ($0, true) }
    }

    func isPillTaken(on day: Date) -> Bool { pillDose(on: day) != nil }

    /// Today's pill, for `PillTodayRow`.
    struct PillToday: Hashable {
        /// Midnight of the pill day.
        var day: Date
        var packDay: Int
        var packLength: Int
        /// False on break days.
        var isPillDay: Bool
        var taken: Date?
        var takenFromHealth = false
        var isNewPack: Bool { packDay == 1 }
    }

    var pillToday: PillToday? {
        guard let pack = pillPack else { return nil }
        let day = currentPillDay
        let packDay = pack.day(on: day)
        let dose = pillDose(on: day)
        return PillToday(day: day, packDay: packDay, packLength: pack.packLength, isPillDay: packDay <= pack.activeDays,
                         taken: dose?.date, takenFromHealth: dose?.fromHealth ?? false)
    }

    /// The current pack's pills as she's logged them: taken, and active days
    /// since she started logging that have no dose. Days before her first
    /// dose aren't judged (they show as before).
    struct PillMarks: Hashable {
        var taken: Set<Int> = []
        var notLogged: Set<Int> = []
    }

    var pillMarks: PillMarks {
        guard let pack = pillPack, let firstDose = pillDoses.min() else { return PillMarks() }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let todayDay = pack.day(on: today)
        let first = pillDay(for: firstDose)
        var marks = PillMarks()
        for d in 1...todayDay {
            guard let date = cal.date(byAdding: .day, value: d - todayDay, to: today) else { continue }
            if isPillTaken(on: date) {
                marks.taken.insert(d)
            } else if d < todayDay, d <= pack.activeDays, date >= first {
                marks.notLogged.insert(d)
            }
        }
        return marks
    }

    // MARK: Taken

    /// "Taken": a dose now, for the current pill day. Clears a reminder
    /// already on screen; the rest are rescheduled (`storeDidChange`).
    func markPillTaken(at date: Date = .now) {
        guard !isPillTaken(on: pillDay(for: date)) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: date) ?? date
        store.data.pillsTaken = store.data.pillsTaken.filter { $0 > cutoff } + [date]
        Task { await PillReminders.clearShown() }
    }

    /// Undo: the doses tapped here for `day`. Apple Health's stay (they're
    /// changed in Health).
    func unmarkPillTaken(on day: Date) {
        let cal = Calendar.current
        store.data.pillsTaken.removeAll { cal.isDate(pillDay(for: $0), inSameDayAs: day) }
    }

    // MARK: Reminders

    /// A settings or log change that moves the reminders.
    static func pillRelevantChange(_ old: AppData, _ new: AppData) -> Bool {
        old.pillsTaken != new.pillsTaken || old.pillReminder != new.pillReminder || old.pillTime != new.pillTime
            || old.pillReadsHealth != new.pillReadsHealth || old.packStartDate != new.packStartDate
            || old.packActiveDays != new.packActiveDays || old.packLength != new.packLength
            || old.birthControl != new.birthControl || old.cycleSetup != new.cycleSetup
    }

    /// Reads Apple Health's doses (when she turned that on), then
    /// reschedules the reminders.
    func updatePill(readHealth: Bool = true) async {
        if readHealth, store.data.pillReadsHealth, !DemoMode.isOn,
           let doses = await PillHealth.doses(health.store, days: 60) {
            if healthPillDoses != doses.taken { healthPillDoses = doses.taken }
            if healthPillHasSchedule != doses.hasSchedule { healthPillHasSchedule = doses.hasSchedule }
        }
        await updatePillReminders()
    }

    /// The week ahead's reminders, or none when they're off or there's no
    /// pack to go by.
    func updatePillReminders() async {
        guard store.data.pillReminder, let pack = pillPack else {
            await PillReminders.cancelAll()
            return
        }
        let plan = PillReminderPlan.reminders(pack: pack, pillTime: store.data.pillTime, now: .now,
                                              isTaken: { isPillTaken(on: $0) },
                                              skipOnTime: appleRemindsPill)
        await PillReminders.reschedule(plan, pillTime: store.data.pillTime, packLength: pack.packLength)
        if DemoMode.pillNotice, !Self.demoNoticeSent, let today = pillToday, today.isPillDay, today.taken == nil {
            Self.demoNoticeSent = true
            let soon = PillReminder(kind: .onTime, fire: .now.addingTimeInterval(10), day: today.day, packDay: today.packDay)
            await PillReminders.add([soon], pillTime: store.data.pillTime, packLength: pack.packLength, exactly: true)
        }
    }

    /// `-demoPillNotice` fired its one notification.
    private static var demoNoticeSent = false

    /// Apple's Medications already reminds her at her pill time: only the
    /// repeat comes from here.
    var appleRemindsPill: Bool { store.data.pillReadsHealth && healthPillHasSchedule }
}
