#if targetEnvironment(simulator)
import HealthKit

/// Fills the simulator's Health app with 11 weeks of made-up nights, heart data and lattes,
/// so every screen has something to show. Never compiled into the phone build.
enum SampleData {
    static func add() async throws {
        var samples: [HKSample] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let bpm = HKUnit.count().unitDivided(by: .minute())

        for i in 1...77 {
            let evening = cal.date(byAdding: .day, value: -i, to: today)!
            let weekday = cal.component(.weekday, from: evening) // 6 = Fri, 7 = Sat
            let weekend = weekday >= 6
            let late = i % 9 == 4
            let bedHour = late ? 26 + i % 2 : weekend ? 25 : 24 // hours after midnight of `evening`
            let bed = cal.date(byAdding: .minute, value: bedHour * 60 + (i * 7) % 50, to: evening)!
            let wake = cal.date(byAdding: .minute, value: (weekend ? 34 : late ? 33 : 32) * 60 + (i * 3) % 40, to: evening)!
            samples.append(HKCategorySample(type: HealthReader.sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: bed, end: wake))

            let morning = cal.date(byAdding: .hour, value: 36, to: evening)!
            let afterLate = (i + 1) % 9 == 4
            samples.append(HKQuantitySample(type: HealthReader.restingHrType, quantity: HKQuantity(unit: bpm, doubleValue: late ? 81 : afterLate ? 79 : 76), start: morning, end: morning))
            samples.append(HKQuantitySample(type: HealthReader.hrvType, quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: late ? 36 : afterLate ? 40 : 44), start: morning, end: morning))
            if i < 17 {
                let latte = cal.date(byAdding: .hour, value: 10, to: evening)!
                samples.append(HKQuantitySample(type: HealthReader.caffeineType, quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: 130), start: latte, end: latte))
            }
        }
        try await HealthReader.store.save(samples)
    }
}
#endif
