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
            waterGoalML: waterGoalTodayML,
            waterGoalHidden: hidesEffortTargets,
            bottleML: store.data.bottleSizeML,
            bedtime: AppDay.date(tonightBedtime, relativeTo: nextWakeDay),
            bedtimeStreak: onTime,
            quickDrink: latte.map { .init(id: $0.id, name: $0.name, mg: $0.caffeineMg) },
            caffeineCutoff: caffeineCutoffShown.map { AppDay.date($0, relativeTo: appDayDate) },
            pill: pillToday.map {
                .init(day: $0.day, packDay: $0.packDay, activeDays: pillPack?.activeDays ?? $0.packLength,
                      packLength: $0.packLength, time: pillTimeHere, taken: $0.taken, breakName: packBreakName)
            },
            stress: AppData.today(store.data.moodLog, date: \.date).last.map { .init(level: $0.stress, date: $0.date) },
            smartAlarmOn: store.data.smartAlarmEnabled,
            wake: lastNightIsFresh ? AppDay.date(lastNight.wake, relativeTo: appDayDate) : nil,
            energy: widgetEnergyCurve
        ).save()
    }

    /// Today's energy curve with where she is at each point, worded as on
    /// Today's "Energy now" tile ("Afternoon dip till 6:07pm").
    private var widgetEnergyCurve: WidgetSnapshot.EnergyCurve? {
        let e = energyToday
        guard let first = e.curve.first else { return nil }
        let day = appDayDate
        let step = e.curve.count > 1 ? e.curve[1].time - first.time : 10
        var spans: [WidgetSnapshot.EnergyCurve.Span] = []
        for p in e.curve {
            let zone = Self.zone(at: p.time, in: e)
            let span = WidgetSnapshot.EnergyCurve.Span(
                from: AppDay.date(p.time, relativeTo: day), title: energyMoment(at: p.time, in: e).title,
                until: zone.map { AppDay.date($0.range.end, relativeTo: day) },
                short: zone.map { WidgetSnapshot.EnergyCurve.shortName($0.kind) })
            if spans.last?.title != span.title || spans.last?.until != span.until { spans.append(span) }
        }
        return .init(start: AppDay.date(first.time, relativeTo: day), step: TimeInterval(step * 60),
                     levels: e.curve.map { Int($0.level.rounded()) }, spans: spans)
    }

    /// Water, pills and stress tapped on a widget (and the smart alarm
    /// switched in Control Center) while the app wasn't running: add them
    /// to the log. Water keeps the id it was saved to
    /// Apple Health with, so nothing is counted or saved twice.
    func importPendingLogs() {
        for p in PendingLogs.takeAll() {
            switch p.kind {
            case let .water(ml, saved):
                addWater(ml: ml, at: p.date, id: p.id, saveToHealth: !saved)
            case .pill:
                markPillTaken(at: p.date)
            case let .stress(level):
                store.data.moodLog.append(AppData.MoodEntry(date: p.date, stress: level))
            case let .smartAlarm(on):
                // Moves the Watch alarm too (`storeDidChange`).
                store.data.smartAlarmEnabled = on
            }
        }
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
