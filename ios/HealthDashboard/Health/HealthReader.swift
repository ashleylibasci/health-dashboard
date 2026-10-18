import HealthKit

/// Everything the app reads from Health, already boiled down to one entry per night or day.
struct HealthData {
    var nights: [Night] = []
    /// Daily average resting heart rate, by local date.
    var restingHr: [String: Double] = [:]
    /// Daily average HRV (SDNN, ms), by local date.
    var hrv: [String: Double] = [:]
    /// Local date of each caffeine log, sorted.
    var caffeine: [String] = []
}

/// Reads sleep, resting HR, HRV and caffeine straight from Apple Health on the phone.
struct HealthReader {
    static let store = HKHealthStore()
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let sleepType = HKCategoryType(.sleepAnalysis)
    static let restingHrType = HKQuantityType(.restingHeartRate)
    static let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    static let caffeineType = HKQuantityType(.dietaryCaffeine)

    static var readTypes: Set<HKObjectType> { [sleepType, restingHrType, hrvType, caffeineType] }

    /// Only the simulator asks to write, so it can add sample data. The real app only reads.
    static var shareTypes: Set<HKSampleType> {
        #if targetEnvironment(simulator)
        [sleepType, restingHrType, hrvType, caffeineType]
        #else
        []
        #endif
    }

    /// Shows Apple's Health permission sheet the first time; after that it returns right away.
    static func requestAccess() async throws {
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    /// Reads roughly the last 13 months, enough for the late-night and exam-week comparisons.
    static func read(days: Int = 400) async throws -> HealthData {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let window = HKQuery.predicateForSamples(withStart: since, end: nil)

        async let sleep = sleepSamples(window)
        async let rhr = dailyAverages(restingHrType, unit: .count().unitDivided(by: .minute()), since: since)
        async let hrv = dailyAverages(hrvType, unit: .secondUnit(with: .milli), since: since)
        async let caffeine = caffeineDates(window)

        return try await HealthData(nights: buildNights(sleep), restingHr: rhr, hrv: hrv, caffeine: caffeine)
    }

    private static func sleepSamples(_ window: NSPredicate) async throws -> [SleepSample] {
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        return try await query.result(for: store)
            .filter { asleep.contains($0.value) }
            .map { s in
                let zone = (s.metadata?[HKMetadataKeyTimeZone] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
                return SleepSample(start: s.startDate, end: s.endDate, timeZone: zone)
            }
    }

    private static func dailyAverages(_ type: HKQuantityType, unit: HKUnit, since: Date) async throws -> [String: Double] {
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil)),
            options: .discreteAverage,
            anchorDate: Calendar.current.startOfDay(for: .now),
            intervalComponents: DateComponents(day: 1)
        )
        var out: [String: Double] = [:]
        try await query.result(for: store).enumerateStatistics(from: since, to: .now) { stats, _ in
            if let q = stats.averageQuantity() { out[Day.key(stats.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    private static func caffeineDates(_ window: NSPredicate) async throws -> [String] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: caffeineType, predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).map { Day.key($0.startDate) }
    }
}
