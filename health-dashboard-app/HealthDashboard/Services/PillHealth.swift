import Foundation
import HealthKit

/// Pill doses from Apple Health (H-A1, "Also read pill doses from Apple
/// Health"). Apple's Medications, and any app that saves doses to Health,
/// record each dose as an `HKMedicationDoseEvent`; a "taken" one counts as
/// Taken here, so she never gets a reminder for a pill she already logged.
/// iOS 26 and later. MyPill keeps its log to itself, so it can't be read.
///
/// Health asks her which medications to share (one sheet, every time she
/// asks); only those are read, so she shares just her pill.
@MainActor
enum PillHealth {
    /// The Medications API exists on this iPhone (iOS 26+).
    static var isSupported: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return HealthKitService.isAvailable
    }

    private static var watching = false

    /// Shows Health's sheet of her medications to pick from. False if it
    /// couldn't be shown (or she cancelled); Health never says what she picked.
    static func requestAccess(_ store: HKHealthStore) async -> Bool {
        guard #available(iOS 26.0, *), HealthKitService.isAvailable else { return false }
        do {
            try await store.requestPerObjectReadAuthorization(for: HKObjectType.userAnnotatedMedicationType(), predicate: nil)
            return true
        } catch {
            return false
        }
    }

    struct Doses {
        /// When each shared medication was marked taken.
        var taken: [Date]
        /// A shared medication has a reminder schedule in Apple's Medications.
        var hasSchedule: Bool
    }

    /// Taken doses of the medications she shared, over the last `days`.
    /// Nil before iOS 26 or when Health can't be read (a locked phone).
    static func doses(_ store: HKHealthStore, days: Int) async -> Doses? {
        guard #available(iOS 26.0, *), HealthKitService.isAvailable else { return nil }
        let active = NSPredicate(format: "%K == NO", HKUserAnnotatedMedicationPredicateKeyPathIsArchived)
        guard let meds = try? await HKUserAnnotatedMedicationQueryDescriptor(predicate: active).result(for: store) else { return nil }
        guard !meds.isEmpty else { return Doses(taken: [], hasSchedule: false) }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: nil),
            NSPredicate(format: "%K == %d", HKPredicateKeyPathStatus, HKMedicationDoseEvent.LogStatus.taken.rawValue),
        ])
        let descriptor = HKSampleQueryDescriptor(predicates: [.sample(type: HKObjectType.medicationDoseEventType(), predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: store) else { return nil }
        return Doses(taken: samples.map(\.startDate), hasSchedule: meds.contains(where: \.hasSchedule))
    }

    /// Health wakes the app when a dose is logged anywhere, so a pending
    /// reminder for that pill is cancelled even while the app is closed.
    /// Call at launch and when she turns the setting on.
    static func startWatching(_ model: AppModel) {
        guard #available(iOS 26.0, *), !watching, HealthKitService.isAvailable, !DemoMode.isOn,
              model.store.data.pillReadsHealth else { return }
        watching = true
        let type = HKObjectType.medicationDoseEventType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak model] _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor in
                await model?.updatePill(readHealth: true)
                completion()
            }
        }
        model.health.store.execute(query)
        model.health.store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }
}
