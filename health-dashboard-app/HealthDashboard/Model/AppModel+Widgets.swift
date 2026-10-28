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
            caffeineNote: caffeineCutoffShown.map { "Cutoff \(BodyLogStyle.shortTime($0))" } ?? "One small drink early",
            waterML: waterTodayML,
            waterGoalML: store.data.waterGoalML,
            bottleML: store.data.bottleSizeML,
            bedtime: AppDay.date(store.data.bedtime, relativeTo: nextWakeDay),
            bedtimeStreak: onTime
        ).save()
    }
}
