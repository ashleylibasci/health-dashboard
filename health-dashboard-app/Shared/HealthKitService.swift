import Foundation
import HealthKit
import HealthCore

/// Reads and writes Apple Health data and turns it into HealthCore models.
/// Everything stays on device.
final class HealthKitService {
    let store = HKHealthStore()
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.appleSleepingWristTemperature),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.vo2Max),
            // Scales "hard training" and an active hour to her (round 4).
            HKQuantityType(.bodyMass),
            HKQuantityType(.dietaryCaffeine),
            HKQuantityType(.dietaryWater),
            HKCategoryType(.menstrualFlow),
            // Fitness age, when she hasn't typed her age in the app.
            HKCharacteristicType(.dateOfBirth),
        ]
        #if os(iOS)
        types.insert(HKQuantityType(.timeInDaylight))
        #endif
        return types
    }

    /// Only the phone writes to Apple Health (drinks logged on the Watch are
    /// saved by the phone), so the Watch asks for read access only.
    private var shareTypes: Set<HKSampleType> {
        #if os(watchOS)
        return []
        #else
        return [HKQuantityType(.dietaryCaffeine), HKQuantityType(.dietaryWater)]
        #endif
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    /// True until she has been asked for Apple Health access (the system
    /// sheet hasn't been shown for these types yet). Apple never tells an
    /// app whether reading was allowed, only whether it asked.
    func needsAuthorizationRequest() async -> Bool {
        guard Self.isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
        return status == .shouldRequest
    }

    /// Saving caffeine to Apple Health was turned off in Settings (the one
    /// permission an app can see). Watch: always false.
    var caffeineWriteDenied: Bool {
        #if os(watchOS)
        return false
        #else
        return store.authorizationStatus(for: HKQuantityType(.dietaryCaffeine)) == .sharingDenied
        #endif
    }

    // MARK: Sleep

    /// Sleep sessions over the last `days`, grouped from Apple Health stage
    /// samples. Samples less than two hours apart belong to the same session,
    /// so waking up for an hour in the night doesn't split it; overnight
    /// (gap starting 9pm–9am) a gap of up to 4 hours still keeps the two
    /// blocks together, so a broken night (biphasic sleep, up at 3am to
    /// study) counts as one night with both blocks. When a source with sleep
    /// stages (Apple Watch) covers a stretch, other sources' plain
    /// "asleep"/"awake" samples for the same minutes are dropped, and any
    /// remaining overlap is counted once. Sessions under 2 hours asleep
    /// (naps) are left out; the caller picks each day's main sleep.
    func sleepSessions(days: Int) async throws -> [SleepSession] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = Self.preferStaged(try await descriptor.result(for: store))

        var sessions: [SleepSession] = []
        var segments: [StageSegment] = []
        var inBed: Date?
        var lastEnd: Date?
        /// Stage minutes already counted, so overlapping sources don't double up.
        var coveredUntil: Date?
        func close() {
            guard let first = segments.first, let end = segments.map(\.end).max() else { segments = []; inBed = nil; return }
            let session = SleepSession(inBed: min(inBed ?? first.start, first.start), wake: end, segments: segments,
                                       alarmUsed: Self.likelyUsedAlarm(wake: end))
            if session.asleepMinutes >= 120 { sessions.append(session) }   // skip naps
            segments = []; inBed = nil; coveredUntil = nil
        }
        func add(_ stage: SleepStage, _ s: HKCategorySample) {
            let from = max(s.startDate, coveredUntil ?? s.startDate)
            guard s.endDate > from else { return }
            segments.append(.init(stage: stage, start: from, end: s.endDate))
            coveredUntil = s.endDate
        }
        for s in samples {
            if let lastEnd, Self.splitsSession(gapFrom: lastEnd, to: s.startDate) { close() }
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .inBed: inBed = min(inBed ?? s.startDate, s.startDate)
            case .awake: add(.awake, s)
            case .asleepREM: add(.rem, s)
            case .asleepDeep: add(.deep, s)
            case .asleepCore, .asleepUnspecified: add(.core, s)
            default: break
            }
            lastEnd = max(lastEnd ?? s.endDate, s.endDate)
        }
        close()
        return sessions
    }

    /// A gap of 2 hours splits a session, except overnight (the gap starts
    /// between 9pm and 9am), where it takes 4.
    static func splitsSession(gapFrom end: Date, to next: Date, calendar: Calendar = .current) -> Bool {
        let gap = next.timeIntervalSince(end)
        guard gap >= 2 * 3600 else { return false }
        let m = Clock.minutesOfDay(end, calendar: calendar)
        let overnight = m >= 21 * 60 || m < 9 * 60
        return !(overnight && gap < 4 * 3600)
    }

    /// Drops plain asleep/awake samples (iPhone, other apps) that overlap a
    /// stretch some source recorded with stages (core, deep, REM).
    private static func preferStaged(_ samples: [HKCategorySample]) -> [HKCategorySample] {
        let stagedValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                      HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let plainValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.awake.rawValue]
        // Merged stretches covered by staged samples, oldest first.
        var covered: [(start: Date, end: Date)] = []
        for s in samples.filter({ stagedValues.contains($0.value) }).sorted(by: { $0.startDate < $1.startDate }) {
            if let last = covered.last, s.startDate <= last.end {
                covered[covered.count - 1].end = max(last.end, s.endDate)
            } else {
                covered.append((s.startDate, s.endDate))
            }
        }
        guard !covered.isEmpty else { return samples }
        let stagedSources = Set(samples.filter { stagedValues.contains($0.value) }.map { $0.sourceRevision.source.bundleIdentifier })
        func overlapsStaged(_ s: HKCategorySample) -> Bool {
            // Last stretch starting before this sample ends.
            var lo = 0, hi = covered.count
            while lo < hi { let mid = (lo + hi) / 2; if covered[mid].start < s.endDate { lo = mid + 1 } else { hi = mid } }
            guard lo > 0 else { return false }
            return covered[lo - 1].end > s.startDate
        }
        return samples.filter { s in
            guard plainValues.contains(s.value), !stagedSources.contains(s.sourceRevision.source.bundleIdentifier) else { return true }
            return !overlapsStaged(s)
        }
    }

    /// Apple Health doesn't record alarms. Weekend mornings count as "free"
    /// (no alarm), whatever time she woke, the way the Munich ChronoType
    /// Questionnaire counts free days. Picking free nights by a late wake
    /// would pick the long nights and bias the sleep-need rebound high.
    static func likelyUsedAlarm(wake: Date) -> Bool {
        !Calendar.current.isDateInWeekend(wake)
    }

    // MARK: Daily values

    /// Daily averages (HRV, resting heart rate, wrist temperature).
    func dailyAverage(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async throws -> [Date: Double] {
        try await daily(id, unit: unit, days: days, options: .discreteAverage)
    }

    /// Daily totals (steps, daylight minutes, caffeine).
    func dailySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async throws -> [Date: Double] {
        try await daily(id, unit: unit, days: days, options: .cumulativeSum)
    }

    private func daily(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int, options: HKStatisticsOptions) async throws -> [Date: Double] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now).addingTimeInterval(86_400)
        let start = cal.date(byAdding: .day, value: -days, to: end)!
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: options, anchorDate: start, intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)
        var out: [Date: Double] = [:]
        for stats in collection.statistics() {
            let q = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
            if let q { out[cal.startOfDay(for: stats.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    /// First day of each period in the last `days`.
    func periodStarts(days: Int) async throws -> [Date] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.menstrualFlow), predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let flowDays = try await descriptor.result(for: store)
            // HKCategoryValueVaginalBleeding is iOS 18 / watchOS 11 only; the
            // older name has the same raw values and works on iOS 17 / watchOS 10.
            .filter { $0.value != HKCategoryValueMenstrualFlow.none.rawValue }
            .map { Calendar.current.startOfDay(for: $0.startDate) }
        // A new period starts after at least two bleed-free days.
        let cal = Calendar.current
        var starts: [Date] = []
        var previous: Date?
        for d in Set(flowDays).sorted() {
            let gap = previous.flatMap { cal.dateComponents([.day], from: $0, to: d).day } ?? 99
            if gap >= 3 { starts.append(d) }
            previous = d
        }
        return starts
    }

    /// Caffeine logged today, as doses at their clock times.
    func caffeineToday() async throws -> [CaffeineDose] {
        let start = Calendar.current.startOfDay(for: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryCaffeine), predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map {
            CaffeineDose(time: Clock.minutesOfDay($0.startDate), mg: Int($0.quantity.doubleValue(for: .gramUnit(with: .milli)).rounded()))
        }
    }

    // MARK: Writing

    /// `id` is stored in the sample's metadata so the entry can be edited or
    /// deleted later.
    func saveCaffeine(mg: Int, at date: Date = .now, id: UUID? = nil) async throws {
        let metadata: [String: Any]? = id.map { [HKMetadataKeyExternalUUID: $0.uuidString] }
        let sample = HKQuantitySample(type: HKQuantityType(.dietaryCaffeine),
                                      quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: Double(mg)),
                                      start: date, end: date, metadata: metadata)
        try await store.save(sample)
    }

    func deleteCaffeine(id: UUID) async throws {
        try await deleteSamples(.dietaryCaffeine, id: id)
    }

    func saveWater(ml: Double, at date: Date = .now, id: UUID? = nil) async throws {
        let metadata: [String: Any]? = id.map { [HKMetadataKeyExternalUUID: $0.uuidString] }
        let sample = HKQuantitySample(type: HKQuantityType(.dietaryWater),
                                      quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
                                      start: date, end: date, metadata: metadata)
        try await store.save(sample)
    }

    func deleteWater(id: UUID) async throws {
        try await deleteSamples(.dietaryWater, id: id)
    }

    /// Deletes the samples this app saved with `id`. Only our own samples can
    /// be deleted, so other apps' entries are never touched.
    /// Deletes what this app saved under `id`: a sample tagged with it, or
    /// (for an entry read in from Health, like the old app's) the sample
    /// whose own id it is.
    private func deleteSamples(_ type: HKQuantityTypeIdentifier, id: UUID) async throws {
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [id.uuidString]),
            HKQuery.predicateForObject(with: id),
        ])
        _ = try await store.deleteObjects(of: HKQuantityType(type), predicate: predicate)
    }

    /// Caffeine or water saved in Apple Health in the last `days`, by any
    /// app: the old Health Dashboard, Shortcuts, or this app.
    func logSamples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async throws -> [HealthLogSample] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map { s in
            HealthLogSample(id: s.uuid,
                            appID: (s.metadata?[HKMetadataKeyExternalUUID] as? String).flatMap(UUID.init(uuidString:)),
                            name: s.metadata?[HKMetadataKeyFoodType] as? String,
                            date: s.startDate,
                            value: s.quantity.doubleValue(for: unit))
        }
    }

    // MARK: Hourly and latest values

    /// Hourly averages (or sums) for today, keyed by hour 0–23.
    func hourlyToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit, sum: Bool) async throws -> [Int: Double] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: .now)),
            options: sum ? .cumulativeSum : .discreteAverage, anchorDate: start, intervalComponents: DateComponents(hour: 1))
        let collection = try await descriptor.result(for: store)
        var out: [Int: Double] = [:]
        for stats in collection.statistics() {
            let q = sum ? stats.sumQuantity() : stats.averageQuantity()
            if let q { out[cal.component(.hour, from: stats.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    /// Hourly averages (or sums) for the `days` days before today, keyed by
    /// the start of each hour. Used for her still-hour heart rate baseline.
    func hourly(_ id: HKQuantityTypeIdentifier, unit: HKUnit, sum: Bool, days: Int) async throws -> [Date: Double] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -days, to: end)!
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: sum ? .cumulativeSum : .discreteAverage, anchorDate: start, intervalComponents: DateComponents(hour: 1))
        let collection = try await descriptor.result(for: store)
        var out: [Date: Double] = [:]
        for stats in collection.statistics() {
            let q = sum ? stats.sumQuantity() : stats.averageQuantity()
            if let q { out[stats.startDate] = q.doubleValue(for: unit) }
        }
        return out
    }

    /// The most recent sample of a type in the last `days`, if any.
    func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async throws -> Double? {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        return try await descriptor.result(for: store).first?.quantity.doubleValue(for: unit)
    }

    /// The average of a type's samples taken during each sleep session
    /// (bed to wake), keyed by the session's wake day. Overnight HRV is
    /// measured at rest, so it compares fairly night to night, unlike a
    /// daily average that grows through the day.
    func overnightAverages(_ id: HKQuantityTypeIdentifier, unit: HKUnit, sessions: [SleepSession], days: Int) async throws -> [Date: Double] {
        let all = try await samples(id, unit: unit, days: days)
        let cal = Calendar.current
        var out: [Date: Double] = [:]
        for s in sessions {
            let xs = all.filter { $0.date >= s.inBed && $0.date <= s.wake }.map(\.value)
            if let m = xs.mean { out[cal.startOfDay(for: s.wake)] = m }
        }
        return out
    }

    /// Her age from her birthday in Apple Health, or nil if it isn't there
    /// or reading it isn't allowed.
    func ageYears() -> Int? {
        guard let birthday = try? store.dateOfBirthComponents(), let date = Calendar.current.date(from: birthday) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }

    /// Every sample of a type in the last `days`, oldest first.
    func samples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async throws -> [(date: Date, value: Double)] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store).map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }
}

/// One caffeine or water entry in Apple Health.
struct HealthLogSample {
    /// Health's own id for the sample.
    var id: UUID
    /// The app entry it was saved from (this app tags what it saves).
    var appID: UUID?
    /// The drink's name, when the app that saved it gave one ("Latte").
    var name: String?
    var date: Date
    var value: Double
}

extension HKUnit {
    static let msUnit = HKUnit.secondUnit(with: .milli)
    static let bpm = HKUnit.count().unitDivided(by: .minute())
    static let vo2 = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
}
