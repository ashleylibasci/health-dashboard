import Foundation
import HealthCore

/// The numbers for the Home Screen and Lock Screen widgets and the Watch
/// complications, saved to the App Group (`WidgetSnapshot`).
extension AppModel {
    func publishWidgetSnapshot() {
        let (number, numberLabel): (Int?, String?) = {
            switch cycleDisplay {
            case let .phases(day, _, _), let .overdue(day, _): return (day, "Day")
            case let .pack(day, _, _): return (day, store.birthControl == .combinedPill ? "Pill" : "Day")
            case let .irregular(days): return (days, days == nil ? nil : "Days")
            case .suppressed, .notTracking: return (nil, nil)
            }
        }()
        let onTime = streaks.first { $0.title == "In bed on time" }?.current ?? 0
        let latte = store.data.savedDrinks.first { $0.name.localizedCaseInsensitiveContains("latte") }
            ?? store.data.savedDrinks.first
        WidgetSnapshot(
            updated: lastRefreshed ?? .now,
            isSample: usingSampleData,
            recovery: recoveryShown,
            recoveryLabel: recoveryLabel,
            energyLeft: Int(energyBankNow.rounded()),
            cycleLine: cycleSummaryLine,
            cycleNumber: number,
            cycleNumberLabel: numberLabel,
            appDayStart: appDayStart,
            caffeineMg: caffeineMgToday,
            caffeineNote: caffeineCutoffShown.map { "Cutoff \(Clock.format($0))" } ?? "One small drink early",
            waterML: waterTodayML,
            waterGoalML: store.data.waterGoalML,
            bottleML: store.data.bottleSizeML,
            bedtime: AppDay.date(store.data.bedtime, relativeTo: nextWakeDay),
            bedtimeStreak: onTime,
            quickDrink: latte.map { .init(id: $0.id, name: $0.name, mg: $0.caffeineMg) },
            caffeineCutoff: caffeineCutoffShown.map { AppDay.date($0, relativeTo: appDayDate) }
        ).save()
    }

    /// The iPhone backup alarm at the smart alarm's latest time, or none.
    func updatePhoneBackupAlarm() {
        PhoneBackupAlarm.shared.update(at: store.data.phoneBackupAlarm ? nextAlarmWindow?.end : nil)
    }

    /// Lattes logged with Siri, Shortcuts or the widget while the app wasn't
    /// running: add them to today's log. Each keeps the id it was saved to
    /// Apple Health with, so nothing is counted or saved twice.
    func importPendingDrinks() {
        for p in PendingDrinks.takeAll() {
            // Saved to Apple Health by the intent already, unless it couldn't.
            logDrink(id: p.entryID, drinkID: p.drinkID, name: p.name, mg: p.mg, at: p.date,
                     saveToHealth: !p.savedToHealth)
        }
    }
}
