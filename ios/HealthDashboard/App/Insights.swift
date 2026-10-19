import Foundation
import HealthKit
import UserNotifications

/// Everything the screens show, worked out from Health, the calendar and the profile.
extension AppModel {
    var today: String { Day.key(.now) }
    /// The last 14 days of recovery (worked out once per refresh; see `derived`).
    var recovery: [RecoveryDay] { Array(derived.recovery.suffix(14)) }
    var recoveryToday: RecoveryDay? { recovery.last.flatMap { $0.date == today ? $0 : nil } }
    var recoveryByDate: [String: Int] { derived.recoveryByDate }
    var usualRecovery: Int? { median(recovery.dropLast().map { Double($0.score) }).map { Int($0.rounded()) } }
    var regularity: Int? { sleepRegularity(health.nights) }
    var fitness: FitnessSummary? { fitnessSummary(health.vo2) }
    var typicalRestingHr: Double? { median((1...28).compactMap { health.restingHr[Day.shift(today, -$0)] }) }
    /// What "relaxed" looks like for her while awake: the quieter quarter of her awake hourly heart
    /// rate over the last month. Stress is measured above this, not above sleeping resting HR, so
    /// sitting in class or walking to it doesn't read as stress.
    var stressBaseline: Double? {
        let awake = health.hourlyHr.filter { (7..<23).contains(Calendar.current.component(.hour, from: $0.key)) }.map(\.value).sorted()
        guard awake.count >= 24 else { return typicalRestingHr.map { $0 + 8 } }
        return awake[awake.count / 4]
    }
    var stress: StressSummary? { stressSummary(health.hourlyHr, resting: stressBaseline) }

    var stressDrivers: [StressFactor] {
        guard let resting = stressBaseline else { return [] }
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
        guard let p = profile else { return nil }
        // A copper IUD has no hormones, so the natural cycle (and its predictions) carry on.
        let naturalCycle = p.cycle == .natural || (p.cycle == .hormonal && p.birthControl == .copperIUD)
        guard naturalCycle || p.cycle == .irregular else { return nil }
        return cycleStatus(health.flow, wristTemp: health.wristTemp, predict: naturalCycle && !p.conditions.contains(.pcos))
    }
    var pack: PackStatus? {
        guard let p = profile, p.cycle == .hormonal, p.birthControl?.hasPlaceboWeek == true else { return nil }
        return packStatus(packStart: p.packStart)
    }

    var sick: SickSignals? {
        guard profile?.prefs.sickAlerts ?? true else { return nil }
        return sickSignals(health, lutealAdjust: cycle.map { $0.phaseKnown && $0.phase == .luteal } ?? false)
    }
    var reasons: [OffReason] { offReasons(data: health, sick: sick, cycle: cycle, exams: exams, hrvChange: recoveryToday?.hrvChange) }

    /// The bedtime the app suggests: your usual school-night time, rounded down to the half hour.
    var bedtimeTarget: Int {
        guard let w = weekend else { return 6 * 60 + 30 }
        return Int(w.schoolNights.bedtime) / 30 * 30
    }
    var streakInfo: Streaks { streaks(health, bedtimeTarget: bedtimeTarget) }

    /// The evening it is right now: until 5am, still last night.
    var tonight: String { Day.evening(.now) }
    /// Caffeine since 5am today (or last night's, if it's before 5am).
    var caffeineToday: [Reading] { health.caffeineLogs.filter { $0.evening == tonight } }
    /// Drinks logged this evening (a 1am drink counts toward last night).
    var drinksTonight: Int { Int(health.drinks.filter { $0.evening == tonight }.reduce(0) { $0 + $1.value }) }
    /// Expected bedtime tonight, from the usual school-night or weekend bedtime.
    var tonightBedtime: Date {
        let minutes = (Day.weekday(tonight) >= 5 ? weekend?.weekendNights.bedtime : weekend?.schoolNights.bedtime) ?? 390
        return Calendar.current.date(byAdding: .minute, value: 18 * 60 + Int(minutes), to: Day.start(tonight))!
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
        snap.headline = sick != nil ? "Body working harder" : r == nil ? "Still learning your normal" : r!.score < 60 ? "Go easy today" : r!.score >= 80 ? "Good to go" : "A steady day"
        snap.cycleDay = cycle?.day ?? pack?.day
        snap.phase = cycle.flatMap { $0.phaseKnown ? $0.phase.rawValue : nil } ?? (pack.map { $0.isBreakWeek ? "Break week" : "Active pills" })
        snap.sleepMinutes = lastNight?.asleepMinutes
        snap.bedBy = clockTime(Double(bedtimeTarget))
        if let r { snap.energy = energyNow(recovery: r.score, activeKcal: health.activeKcal[today] ?? 0, stressedHours: stress?.stressedHours ?? 0).left }
        snap.streakNights = streakInfo.bedtimeNights
        snap.caffeineMg = caffeineToday.reduce(0) { $0 + $1.value }
        snap.caffeineDay = tonight
        snap.bottleMl = bottleMl
        snap.updated = .now
        snap.restingHr = health.restingHr[today].map { Int($0.rounded()) }
        snap.hrv = health.hrv[today].map { Int($0.rounded()) }
        snap.hrUp = (r?.restingHrChange ?? 0) >= 3
        snap.hrvDown = (r?.hrvChange ?? 0) <= -0.1
        if let c = cycle {
            snap.typicalLength = c.typicalLength
            snap.periodLength = c.periodLength
            snap.ovulationDay = c.ovulationDay ?? (c.typicalLength - 14)
            snap.daysToPeriod = c.nextStart.map { Day.between(today, $0) }
            snap.tempDelta = temperatureDeviation(health.wristTemp, days: 1).last?.value
        }
        snap.caffeineAtBed = caffeineLeft(health.caffeineLogs, at: tonightBedtime)
        if let exam = upcomingExams.first(where: { (1...3).contains(Day.between(today, $0.date)) }) {
            let d = Day.between(today, exam.date)
            snap.examNote = "\(exam.title.split(separator: " ").last.map(String.init) ?? "Exam") \(d == 1 ? "tomorrow" : "in \(d) days"). Tonight counts."
        }
        snap.sick = sick != nil
        snap.sickTonight = sick != nil ? "Tonight: bed by \(clockTime(Double(max(240, bedtimeTarget - 45)))), extra water." : nil
        snap.darkAtNight = p.prefs.darkWatchAtNight
        snap.bedtimeMinutes = bedtimeTarget
        snap.save()
        WatchSync.shared.send(snap)
    }

    // MARK: Logging to Apple Health

    func logCaffeine(_ mg: Double, name: String? = nil, at date: Date = .now) async {
        let meta: [String: Any] = name.map { [HKMetadataKeyFoodType: $0] } ?? [:]
        await save([HKQuantitySample(type: HealthReader.caffeineType, quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: mg),
                                     start: date, end: date, metadata: meta)])
    }

    /// Moves a caffeine log to a new time or amount. Health only lets an app change samples it saved,
    /// so logs from Shortcuts or other apps have to be changed in the Health app.
    @discardableResult
    func editCaffeine(_ log: Reading, mg: Double, at date: Date) async -> Bool {
        guard await deleteSample(log, type: HealthReader.caffeineType) else { return false }
        await logCaffeine(mg, name: log.name, at: date)
        return lastLogError == nil
    }

    @discardableResult
    func deleteCaffeine(_ log: Reading) async -> Bool {
        guard await deleteSample(log, type: HealthReader.caffeineType) else { return false }
        await afterChange()
        return true
    }

    func logDrink(_ name: String? = nil, at date: Date = .now) async {
        let meta: [String: Any] = name.map { [HKMetadataKeyFoodType: $0] } ?? [:]
        await save([HKQuantitySample(type: HealthReader.alcoholType, quantity: HKQuantity(unit: .count(), doubleValue: 1), start: date, end: date, metadata: meta)])
    }

    /// Logs part of a water bottle: 0.25, 0.5 or 1.
    func logWater(bottles: Double = 1) async {
        await save([HKQuantitySample(type: HealthReader.waterType, quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: bottleMl * bottles), start: .now, end: .now)])
    }

    /// What's logged for a day: flow level (0 no flow, 1 spotting, 2 light, 3 medium, 4 heavy) and symptoms.
    func dayLog(_ day: String) -> (flow: Int?, symptoms: Set<Symptom>) {
        (health.flow[day] ?? (health.spotting.contains(day) ? 1 : nil), health.symptoms[day] ?? [])
    }

    /// Saves one day's flow and symptoms, replacing whatever this app saved for that day before,
    /// so fixing a mistake never stacks up duplicates. Spotting is saved as spotting (between-period
    /// bleeding), never as a period day. Pass nil flow and no symptoms to clear the day.
    @discardableResult
    func saveDay(_ day: String, flow: Int?, symptoms: Set<Symptom>) async -> Bool {
        if isDemoMode { return true }
        lastLogError = nil
        let start = Day.start(day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let mine = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            HKQuery.predicateForObjects(from: .default()),
        ])
        for type in [HealthReader.menstrualFlowType, HealthReader.spottingType] + Symptom.allCases.map(\.type) {
            _ = try? await HealthReader.store.deleteObjects(of: type, predicate: mine)
        }
        var samples: [HKObject] = []
        if let flow {
            if flow == 1 {
                samples.append(HKCategorySample(type: HealthReader.spottingType, value: HKCategoryValue.notApplicable.rawValue, start: start, end: end.addingTimeInterval(-1)))
            } else {
                let value: HKCategoryValueVaginalBleeding = switch flow { case 2: .light; case 3: .medium; case 4: .heavy; default: .none }
                samples.append(HKCategorySample(type: HealthReader.menstrualFlowType, value: value.rawValue, start: start, end: end.addingTimeInterval(-1),
                                                metadata: [HKMetadataKeyMenstrualCycleStart: flow >= 2 && startsNewPeriod(day, flow: health.flow)]))
            }
        }
        // Symptoms sit at noon of that day (or now, for today), so they stay on the right day.
        let at = day == today ? Date.now : start.addingTimeInterval(12 * 3600)
        for symptom in symptoms {
            samples.append(HKCategorySample(type: symptom.type, value: 0, start: at, end: at))
        }
        guard !samples.isEmpty else {
            await afterChange()
            return true
        }
        return await save(samples)
    }

    /// Stress 1 (very calm) … 5 (very stressed), saved as a State of Mind.
    func logStress(_ level: Int) async {
        let valence = [0.8, 0.4, 0, -0.4, -0.8][max(0, min(4, level - 1))]
        let labels: [HKStateOfMind.Label] = level >= 4 ? [.stressed] : level <= 2 ? [.calm] : [.content]
        await save([HKStateOfMind(date: .now, kind: .momentaryEmotion, valence: valence, labels: labels, associations: [.education])])
    }

    @discardableResult
    func logSymptom(_ symptom: Symptom) async -> Bool {
        await save([HKCategorySample(type: symptom.type, value: 0, start: .now, end: .now)])
    }

    /// Every save clears the last error, re-reads Health, and refreshes the widgets and Watch.
    @discardableResult
    private func save(_ samples: [HKObject]) async -> Bool {
        if isDemoMode { return true }
        lastLogError = nil
        do {
            try await HealthReader.store.save(samples)
            await afterChange()
            return true
        } catch {
            lastLogError = error.localizedDescription
            return false
        }
    }

    private func deleteSample(_ log: Reading, type: HKSampleType) async -> Bool {
        if isDemoMode { return true }
        lastLogError = nil
        guard log.mine, let uuid = log.uuid else {
            lastLogError = "This one was logged by another app (like Shortcuts), so only the Health app can change it: Health → Browse → Nutrition → Caffeine."
            return false
        }
        do {
            _ = try await HealthReader.store.deleteObjects(of: type, predicate: HKQuery.predicateForObject(with: uuid))
            return true
        } catch {
            lastLogError = "Couldn’t change it in Apple Health: \(error.localizedDescription)"
            return false
        }
    }

    private func afterChange() async {
        await refreshHealth()
        publishWidgetSnapshot()
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
        // Never prompt from here; the welcome flow and Settings ask, with the reason shown.
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
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
    case cramps = "Cramps", bloated = "Bloated", tired = "Tired", headache = "Headache", cravings = "Cravings",
         moodChanges = "Mood swings", breastTenderness = "Tender breasts", backPain = "Back pain", nausea = "Nausea", acne = "Acne",
         soreThroat = "Sore throat", stuffyNose = "Stuffy nose", cough = "Cough", fever = "Fever"
    var id: String { rawValue }

    var type: HKCategoryType {
        switch self {
        case .cramps: HKCategoryType(.abdominalCramps)
        case .bloated: HKCategoryType(.bloating)
        case .tired: HKCategoryType(.fatigue)
        case .headache: HKCategoryType(.headache)
        case .cravings: HKCategoryType(.appetiteChanges)
        case .moodChanges: HKCategoryType(.moodChanges)
        case .breastTenderness: HKCategoryType(.breastPain)
        case .backPain: HKCategoryType(.lowerBackPain)
        case .nausea: HKCategoryType(.nausea)
        case .acne: HKCategoryType(.acne)
        case .soreThroat: HKCategoryType(.soreThroat)
        case .stuffyNose: HKCategoryType(.sinusCongestion)
        case .cough: HKCategoryType(.coughing)
        case .fever: HKCategoryType(.fever)
        }
    }

    static let cycle: [Symptom] = [.cramps, .bloated, .tired, .headache, .cravings, .moodChanges, .breastTenderness, .backPain, .nausea, .acne]
    static let cold: [Symptom] = [.soreThroat, .stuffyNose, .tired, .headache, .cough, .fever]
}
