import Foundation
import HealthKit
import UserNotifications

/// Everything the screens show, worked out from Health, the calendar and the profile.
extension AppModel {
    var today: String { Day.key(.now) }
    var recovery: [RecoveryDay] { recoveryDays(health.nights, restingHr: health.restingHr, hrv: health.hrv) }
    var recoveryToday: RecoveryDay? { recovery.last.flatMap { $0.date == today ? $0 : nil } }
    var recoveryByDate: [String: Int] {
        Dictionary(recoveryDays(health.nights, restingHr: health.restingHr, hrv: health.hrv, days: 180).map { ($0.date, $0.score) }, uniquingKeysWith: { a, _ in a })
    }
    var usualRecovery: Int? { median(recovery.dropLast().map { Double($0.score) }).map { Int($0.rounded()) } }
    var regularity: Int? { sleepRegularity(health.nights) }
    var fitness: FitnessSummary? { fitnessSummary(health.vo2) }
    var typicalRestingHr: Double? { median((1...28).compactMap { health.restingHr[Day.shift(today, -$0)] }) }
    var stress: StressSummary? { stressSummary(health.hourlyHr, resting: typicalRestingHr) }

    var stressDrivers: [StressFactor] {
        guard let resting = typicalRestingHr else { return [] }
        let busy = Set(events.filter { isExam($0.title) || $0.title.range(of: "\\b(due|deadline)\\b", options: [.regularExpression, .caseInsensitive]) != nil }.map(\.date))
        var lateLuteal = Set<String>()
        if let c = cycle, profile?.cycle == .natural {
            for back in 0..<120 {
                let date = Day.shift(today, -back)
                let day = Day.between(c.lastStart, date) + 1
                let len = c.typicalLength
                let cycleDay = ((day - 1) % len + len) % len + 1
                if cycleDay >= len - 5 { lateLuteal.insert(date) }
            }
        }
        return stressFactors(daily: dailyStress(health.hourlyHr, resting: resting), nights: health.nights, exercise: health.exerciseMinutes, busyDays: busy, lateLutealDays: lateLuteal)
    }

    var cycle: CycleStatus? {
        guard let p = profile, p.cycle == .natural || p.cycle == .irregular else { return nil }
        return cycleStatus(health.flow, wristTemp: health.wristTemp, predict: p.cycle == .natural && !p.conditions.contains(.pcos))
    }
    var pack: PackStatus? {
        guard let p = profile, p.cycle == .hormonal, p.birthControl?.hasPlaceboWeek == true else { return nil }
        return packStatus(packStart: p.packStart)
    }

    var sick: SickSignals? {
        guard profile?.prefs.sickAlerts ?? true else { return nil }
        return sickSignals(health, lutealAdjust: cycle?.phase == .luteal)
    }
    var reasons: [OffReason] { offReasons(data: health, sick: sick, cycle: cycle, exams: exams, hrvChange: recoveryToday?.hrvChange) }

    /// The bedtime the app suggests: your usual school-night time, rounded down to the half hour.
    var bedtimeTarget: Int {
        guard let w = weekend else { return 6 * 60 + 30 }
        return Int(w.schoolNights.bedtime) / 30 * 30
    }
    var streakInfo: Streaks { streaks(health, bedtimeTarget: bedtimeTarget) }

    var caffeineToday: [Reading] { health.caffeineLogs.filter { $0.day == today } }
    /// Expected bedtime tonight as a time, from the usual school-night or weekend bedtime.
    var tonightBedtime: Date {
        let evening = Calendar.current.startOfDay(for: .now)
        let minutes = (Day.weekday(today) >= 5 ? weekend?.weekendNights.bedtime : weekend?.schoolNights.bedtime) ?? 390
        return evening.addingTimeInterval((18 * 60 + minutes) * 60)
    }
    var bottleMl: Double { profile?.bottleMl ?? 710 }
    /// Bottles drunk today, in quarters.
    var bottlesToday: Double { ((health.waterMl[today] ?? 0) / bottleMl * 4).rounded() / 4 }

    // MARK: Widgets

    /// Hands the widgets today's numbers through the shared App Group.
    func publishWidgetSnapshot() {
        guard let p = profile else { return }
        let r = recoveryToday
        var snap = WidgetSnapshot()
        snap.name = p.firstName
        snap.recovery = r?.score
        snap.recoveryLabel = r?.label ?? ""
        snap.headline = sick != nil ? "Body working harder" : (r?.score ?? 80) < 60 ? "Go easy today" : (r?.score ?? 0) >= 80 ? "Good to go" : "A steady day"
        snap.cycleDay = cycle?.day ?? pack?.day
        snap.phase = cycle?.phase.rawValue ?? (pack.map { $0.isBreakWeek ? "Break week" : "Active pills" })
        snap.sleepMinutes = lastNight?.asleepMinutes
        snap.bedBy = clockTime(Double(bedtimeTarget))
        if let r { snap.energy = energyNow(recovery: r.score, activeKcal: health.activeKcal[today] ?? 0, stressedHours: stress?.stressedHours ?? 0).left }
        snap.streakNights = streakInfo.bedtimeNights
        snap.caffeineMg = caffeineToday.reduce(0) { $0 + $1.value }
        snap.caffeineDay = today
        snap.updated = .now
        snap.save()
    }

    // MARK: Logging to Apple Health

    func logCaffeine(_ mg: Double) async {
        await save(HKQuantitySample(type: HealthReader.caffeineType, quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: mg), start: .now, end: .now))
    }

    func logDrink() async {
        await save(HKQuantitySample(type: HealthReader.alcoholType, quantity: HKQuantity(unit: .count(), doubleValue: 1), start: .now, end: .now))
    }

    /// Logs part of a water bottle: 0.25, 0.5 or 1.
    func logWater(bottles: Double = 1) async {
        await save(HKQuantitySample(type: HealthReader.waterType, quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: bottleMl * bottles), start: .now, end: .now))
    }

    /// Flow: 0 none, 2 light, 3 medium, 4 heavy. The first flow day after a gap starts a new cycle.
    func logFlow(_ level: Int, startsPeriod: Bool) async {
        let value: HKCategoryValueVaginalBleeding = switch level { case 2: .light; case 3: .medium; case 4: .heavy; default: .none }
        let start = Calendar.current.startOfDay(for: .now)
        await save(HKCategorySample(type: HealthReader.menstrualFlowType, value: value.rawValue, start: start, end: start.addingTimeInterval(86399),
                                    metadata: [HKMetadataKeyMenstrualCycleStart: startsPeriod && level > 0]))
    }

    /// Stress 1 (very calm) … 5 (very stressed), saved as a State of Mind.
    func logStress(_ level: Int) async {
        let valence = [0.8, 0.4, 0, -0.4, -0.8][max(0, min(4, level - 1))]
        let labels: [HKStateOfMind.Label] = level >= 4 ? [.stressed] : level <= 2 ? [.calm] : [.content]
        await save(HKStateOfMind(date: .now, kind: .momentaryEmotion, valence: valence, labels: labels, associations: [.education]))
    }

    func logSymptom(_ symptom: Symptom) async {
        await save(HKCategorySample(type: symptom.type, value: HKCategoryValueSeverity.unspecified.rawValue, start: .now, end: .now))
    }

    private func save(_ sample: HKObject) async {
        if isDemoMode { return }
        do {
            try await HealthReader.store.save(sample)
            await refreshHealth()
        } catch {
            lastLogError = error.localizedDescription
        }
    }

    // MARK: Pill pack

    func startNewPack() { profile?.packStart = Calendar.current.startOfDay(for: .now) }
    func togglePillTaken() {
        guard var p = profile else { return }
        if p.pillsTaken.contains(today) { p.pillsTaken.remove(today) } else { p.pillsTaken.insert(today) }
        profile = p
    }

    // MARK: Notifications

    /// Local notifications only: the evening before an exam, and when the getting-sick signals show up.
    func scheduleNotifications() async {
        guard !isDemoMode else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let oldExams = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("exam-") }
        center.removePendingNotificationRequests(withIdentifiers: oldExams)
        for exam in upcomingExams where Day.between(today, exam.date) >= 1 {
            let evening = Day.shift(exam.date, -1)
            var when = DateComponents()
            let parts = evening.split(separator: "-").compactMap { Int($0) }
            when.year = parts[0]; when.month = parts[1]; when.day = parts[2]; when.hour = 21
            let content = UNMutableNotificationContent()
            content.title = "\(exam.title) tomorrow"
            content.body = "Aim to be asleep by \(clockTime(Double(bedtimeTarget))). Sleep does more for the exam than late studying."
            try? await center.add(UNNotificationRequest(identifier: "exam-\(exam.date)-\(exam.title)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }
        if let s = sick, UserDefaults.standard.string(forKey: "sickNotified") != today {
            UserDefaults.standard.set(today, forKey: "sickNotified")
            let content = UNMutableNotificationContent()
            content.title = "Your body’s working harder than usual"
            content.body = "\(s.count) signals moved together. Could be a bug coming on, or stress. A guess, not a diagnosis."
            try? await center.add(UNNotificationRequest(identifier: "sick-\(today)", content: content, trigger: nil))
        }
    }
}

enum Symptom: String, CaseIterable, Identifiable {
    case bloated = "Bloated", tired = "Tired", cramps = "Cramps", headache = "Headache", cravings = "Cravings",
         soreThroat = "Sore throat", stuffyNose = "Stuffy nose", cough = "Cough", fever = "Fever", acne = "Acne"
    var id: String { rawValue }

    var type: HKCategoryType {
        switch self {
        case .bloated: HKCategoryType(.bloating)
        case .tired: HKCategoryType(.fatigue)
        case .cramps: HKCategoryType(.abdominalCramps)
        case .headache: HKCategoryType(.headache)
        case .cravings: HKCategoryType(.appetiteChanges)
        case .soreThroat: HKCategoryType(.soreThroat)
        case .stuffyNose: HKCategoryType(.sinusCongestion)
        case .cough: HKCategoryType(.coughing)
        case .fever: HKCategoryType(.fever)
        case .acne: HKCategoryType(.acne)
        }
    }

    static let cycle: [Symptom] = [.bloated, .tired, .cramps, .headache, .cravings]
    static let cold: [Symptom] = [.soreThroat, .stuffyNose, .tired, .headache, .cough, .fever]
}
