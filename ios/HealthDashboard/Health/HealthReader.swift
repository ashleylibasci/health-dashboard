import HealthKit

/// One timed reading, like a latte at 9:40am or a State of Mind log.
struct Reading: Equatable {
    var date: Date
    var value: Double
    var day: String { Day.key(date) }
}

/// Everything the app reads from Health, already boiled down to one entry per night or day.
struct HealthData {
    var nights: [Night] = []
    /// Daily average resting heart rate, by local date.
    var restingHr: [String: Double] = [:]
    /// Daily average HRV (SDNN, ms), by local date.
    var hrv: [String: Double] = [:]
    /// Local date of each caffeine log, sorted.
    var caffeine: [String] { caffeineLogs.map(\.day) }
    /// Each caffeine log with its time and milligrams.
    var caffeineLogs: [Reading] = []
    /// VO2 max readings (mL/kg/min), oldest first.
    var vo2: [Reading] = []
    /// Daily totals, by local date.
    var exerciseMinutes: [String: Double] = [:]
    var steps: [String: Double] = [:]
    var activeKcal: [String: Double] = [:]
    var restingKcal: [String: Double] = [:]
    var waterMl: [String: Double] = [:]
    /// Each alcoholic drink logged, with its time.
    var drinks: [Reading] = []
    /// Menstrual flow by date: 1 unspecified, 2 light, 3 medium, 4 heavy, 0 = logged "none".
    var flow: [String: Int] = [:]
    /// Nightly wrist temperature (°C) by the date she woke up.
    var wristTemp: [String: Double] = [:]
    /// Daily average breathing rate while asleep, per minute.
    var respiratory: [String: Double] = [:]
    /// State of Mind logs: valence from −1 (very unpleasant) to 1 (very pleasant).
    var moods: [Reading] = []
    /// Average heart rate per hour for the last 30 days, keyed by the hour's start.
    var hourlyHr: [Date: Double] = [:]
}

/// Reads sleep, resting HR, HRV and caffeine straight from Apple Health on the phone.
struct HealthReader {
    static let store = HKHealthStore()
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let sleepType = HKCategoryType(.sleepAnalysis)
    static let restingHrType = HKQuantityType(.restingHeartRate)
    static let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    static let caffeineType = HKQuantityType(.dietaryCaffeine)
    static let vo2MaxType = HKQuantityType(.vo2Max)
    static let menstrualFlowType = HKCategoryType(.menstrualFlow)
    static let wristTempType = HKQuantityType(.appleSleepingWristTemperature)
    static let stateOfMindType = HKObjectType.stateOfMindType()
    static let alcoholType = HKQuantityType(.numberOfAlcoholicBeverages)
    static let waterType = HKQuantityType(.dietaryWater)
    static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    static let basalEnergyType = HKQuantityType(.basalEnergyBurned)
    static let stepsType = HKQuantityType(.stepCount)
    static let exerciseType = HKQuantityType(.appleExerciseTime)
    static let heartRateType = HKQuantityType(.heartRate)
    static let respiratoryType = HKQuantityType(.respiratoryRate)
    static let oxygenType = HKQuantityType(.oxygenSaturation)

    /// Everything any screen uses, asked for once in the welcome flow.
    static var readTypes: Set<HKObjectType> {
        [sleepType, restingHrType, hrvType, caffeineType, vo2MaxType, menstrualFlowType, wristTempType,
         stateOfMindType, alcoholType, waterType, activeEnergyType, basalEnergyType, stepsType,
         exerciseType, heartRateType, respiratoryType, oxygenType]
    }

    /// What the app can log for you: drinks, water, period days and how you feel.
    /// The simulator can also write sample sleep and heart data for testing.
    static var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [caffeineType, alcoholType, waterType, menstrualFlowType, stateOfMindType]
        types.formUnion(Symptom.allCases.map(\.type))
        #if targetEnvironment(simulator)
        types.formUnion([sleepType, restingHrType, hrvType])
        #endif
        return types
    }

    /// Shows Apple's Health permission sheet the first time; after that it returns right away.
    static func requestAccess() async throws {
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    /// Reads roughly the last 13 months, enough for the late-night and exam-week comparisons.
    static func read(days: Int = 400) async throws -> HealthData {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let window = HKQuery.predicateForSamples(withStart: since, end: nil)

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: .now))!

        async let sleep = sleepSamples(window)
        async let rhr = daily(restingHrType, .discreteAverage, unit: bpm, since: since)
        async let hrv = daily(hrvType, .discreteAverage, unit: .secondUnit(with: .milli), since: since)
        async let caffeine = readings(caffeineType, unit: .gramUnit(with: .milli), window)
        async let vo2 = readings(vo2MaxType, unit: HKUnit(from: "ml/kg*min"), HKQuery.predicateForSamples(withStart: nil, end: nil))
        async let exercise = daily(exerciseType, .cumulativeSum, unit: .minute(), since: since)
        async let steps = daily(stepsType, .cumulativeSum, unit: .count(), since: since)
        async let active = daily(activeEnergyType, .cumulativeSum, unit: .kilocalorie(), since: since)
        async let resting = daily(basalEnergyType, .cumulativeSum, unit: .kilocalorie(), since: since)
        async let water = daily(waterType, .cumulativeSum, unit: .literUnit(with: .milli), since: since)
        async let drinks = readings(alcoholType, unit: .count(), window)
        async let flow = flowDays(window)
        async let temp = wakeDayReadings(wristTempType, unit: .degreeCelsius(), window)
        async let resp = daily(respiratoryType, .discreteAverage, unit: bpm, since: since)
        async let moods = moodReadings(window)
        async let hourly = hourlyAverages(heartRateType, unit: bpm, since: monthAgo)

        return try await HealthData(
            nights: buildNights(sleep), restingHr: rhr, hrv: hrv, caffeineLogs: caffeine, vo2: vo2,
            exerciseMinutes: exercise, steps: steps, activeKcal: active, restingKcal: resting, waterMl: water,
            drinks: drinks, flow: flow, wristTemp: temp, respiratory: resp, moods: moods, hourlyHr: hourly
        )
    }

    private static func sleepSamples(_ window: NSPredicate) async throws -> [SleepSample] {
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).compactMap { s in
            let stage: SleepSample.Stage
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            case .asleepUnspecified: stage = .asleep
            case .awake: stage = .awake
            default: return nil // in bed
            }
            let zone = (s.metadata?[HKMetadataKeyTimeZone] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
            return SleepSample(start: s.startDate, end: s.endDate, timeZone: zone, stage: stage)
        }
    }

    /// One value per local day: a daily average or a daily total.
    private static func daily(_ type: HKQuantityType, _ options: HKStatisticsOptions, unit: HKUnit, since: Date) async throws -> [String: Double] {
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil)),
            options: options,
            anchorDate: Calendar.current.startOfDay(for: .now),
            intervalComponents: DateComponents(day: 1)
        )
        var out: [String: Double] = [:]
        try await query.result(for: store).enumerateStatistics(from: since, to: .now) { stats, _ in
            let q = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
            if let q { out[Day.key(stats.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    /// Average per hour, for the stress chart.
    private static func hourlyAverages(_ type: HKQuantityType, unit: HKUnit, since: Date) async throws -> [Date: Double] {
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil)),
            options: .discreteAverage,
            anchorDate: since,
            intervalComponents: DateComponents(hour: 1)
        )
        var out: [Date: Double] = [:]
        try await query.result(for: store).enumerateStatistics(from: since, to: .now) { stats, _ in
            if let q = stats.averageQuantity() { out[stats.startDate] = q.doubleValue(for: unit) }
        }
        return out
    }

    private static func readings(_ type: HKQuantityType, unit: HKUnit, _ window: NSPredicate) async throws -> [Reading] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).map { Reading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    /// Overnight readings keyed by the morning they ended on.
    private static func wakeDayReadings(_ type: HKQuantityType, unit: HKUnit, _ window: NSPredicate) async throws -> [String: Double] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        var out: [String: Double] = [:]
        for s in try await query.result(for: store) { out[Day.key(s.endDate)] = s.quantity.doubleValue(for: unit) }
        return out
    }

    private static func flowDays(_ window: NSPredicate) async throws -> [String: Int] {
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: menstrualFlowType, predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        var out: [String: Int] = [:]
        for s in try await query.result(for: store) {
            let level: Int
            switch HKCategoryValueVaginalBleeding(rawValue: s.value) {
            case .light: level = 2
            case .medium: level = 3
            case .heavy: level = 4
            case .none: level = 0
            default: level = 1
            }
            out[Day.key(s.startDate)] = max(out[Day.key(s.startDate)] ?? 0, level)
        }
        return out
    }

    private static func moodReadings(_ window: NSPredicate) async throws -> [Reading] {
        let query = HKSampleQueryDescriptor(
            predicates: [.stateOfMind(window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).map { Reading(date: $0.startDate, value: $0.valence) }
    }
}
