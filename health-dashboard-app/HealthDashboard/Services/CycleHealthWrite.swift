import Foundation
import HealthKit
import HealthCore

/// Saves bleeding, symptoms and her birth-control method to Apple Health
/// (G3), when she turns it on, so her history survives a reinstall and
/// Apple's Cycle Tracking sees the same record. Each entry is saved once
/// under its own sync identifier ("flow-<id>"), and removed from Health
/// when she deletes it here. Turning it off stops saving and leaves what's
/// in Health alone.
@MainActor
enum CycleHealthWrite {
    /// A logged symptom's Apple Health type, where there is one.
    static func symptomType(_ name: String) -> HKCategoryTypeIdentifier? {
        switch name {
        case "Cramps": .abdominalCramps
        case "Headache": .headache
        case "Bloating": .bloating
        case "Acne": .acne
        case "Tender breasts": .breastPain
        case "Mood swings": .moodChanges
        case "Fatigue": .fatigue
        case "Cravings": .appetiteChanges
        case "Back pain": .lowerBackPain
        case "Nausea": .nausea
        case "Vomiting": .vomiting
        case "Diarrhea": .diarrhea
        default: nil
        }
    }

    static var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKCategoryType(.menstrualFlow), HKCategoryType(.intermenstrualBleeding),
                                        HKCategoryType(.contraceptive)]
        for name in ["Cramps", "Headache", "Bloating", "Acne", "Tender breasts", "Mood swings", "Fatigue",
                     "Cravings", "Back pain", "Nausea", "Vomiting", "Diarrhea"] {
            if let id = symptomType(name) { types.insert(HKCategoryType(id)) }
        }
        return types
    }

    /// Asks to save these types (Health's sheet shows the first time).
    static func requestAccess(_ store: HKHealthStore) async -> Bool {
        guard HealthKitService.isAvailable else { return false }
        return (try? await store.requestAuthorization(toShare: writeTypes, read: [])) != nil
    }

    /// One sample this app keeps in Health, by sync identifier.
    struct Planned {
        var id: String
        var sample: HKCategorySample
    }

    /// Everything her log says should be in Health.
    static func planned(_ data: AppData, method: BirthControl?) -> [Planned] {
        let cal = Calendar.current
        var out: [Planned] = []
        func meta(_ id: String) -> [String: Any] { [HKMetadataKeySyncIdentifier: id, HKMetadataKeySyncVersion: 1] }
        // Bleeding days: a new period starts after two days without bleeding.
        let bleedDays = Set(data.flowLog.filter { $0.flow != .none && $0.flow != .spotting }.map { cal.startOfDay(for: $0.date) })
        for entry in data.flowLog where entry.flow != .none {
            let id = "flow-\(entry.id.uuidString)"
            let day = cal.startOfDay(for: entry.date)
            if entry.flow == .spotting {
                out.append(Planned(id: id, sample: HKCategorySample(type: HKCategoryType(.intermenstrualBleeding),
                                                                    value: HKCategoryValue.notApplicable.rawValue,
                                                                    start: entry.date, end: entry.date, metadata: meta(id))))
                continue
            }
            let isStart = !(1...2).contains { back in cal.date(byAdding: .day, value: -back, to: day).map(bleedDays.contains) ?? false }
            // HKCategoryValueVaginalBleeding is iOS 18 only; the older name
            // has the same raw values.
            let value: HKCategoryValueMenstrualFlow = switch entry.flow {
            case .light: .light
            case .heavy: .heavy
            default: .medium
            }
            var m = meta(id)
            m[HKMetadataKeyMenstrualCycleStart] = isStart
            out.append(Planned(id: id, sample: HKCategorySample(type: HKCategoryType(.menstrualFlow), value: value.rawValue,
                                                                start: entry.date, end: entry.date, metadata: m)))
        }
        for entry in data.symptomLog {
            for name in entry.symptoms {
                guard let type = symptomType(name) else { continue }
                let id = "symptom-\(entry.id.uuidString)-\(name)"
                let value: Int = switch type {
                case .moodChanges: HKCategoryValuePresence.present.rawValue
                case .appetiteChanges: HKCategoryValueAppetiteChanges.increased.rawValue
                default: HKCategoryValueSeverity.unspecified.rawValue
                }
                out.append(Planned(id: id, sample: HKCategorySample(type: HKCategoryType(type), value: value,
                                                                    start: entry.date, end: entry.date, metadata: meta(id))))
            }
        }
        // Her method, from the day she started it (when the app knows it).
        if let method, let since = data.methodChangedDate {
            let value = contraceptive(method)
            let start = cal.startOfDay(for: since)
            let id = "contraceptive-\(value.rawValue)-\(Int(start.timeIntervalSince1970))"
            out.append(Planned(id: id, sample: HKCategorySample(type: HKCategoryType(.contraceptive), value: value.rawValue,
                                                                start: start, end: start, metadata: meta(id))))
        }
        return out
    }

    static func contraceptive(_ method: BirthControl) -> HKCategoryValueContraceptive {
        switch method {
        case .combinedPill, .miniPill: .oral
        case .hormonalIUD, .copperIUD: .intrauterineDevice
        case .implant: .implant
        case .shot: .injection
        case .patch: .patch
        case .ring: .intravaginalRing
        }
    }

    /// Saves what's new and removes what she deleted here. Returns the ids
    /// now in Health, or nil when Health couldn't be written (nothing is
    /// recorded as saved then, so it's tried again later).
    static func sync(_ store: HKHealthStore, data: AppData, method: BirthControl?) async -> Set<String>? {
        guard HealthKitService.isAvailable else { return nil }
        let plan = planned(data, method: method)
        let wanted = Set(plan.map(\.id))
        let new = plan.filter { !data.cycleHealthSaved.contains($0.id) }
        let gone = data.cycleHealthSaved.subtracting(wanted)
        if !new.isEmpty {
            do { try await store.save(new.map(\.sample)) } catch { return nil }
        }
        if !gone.isEmpty {
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: Array(gone))
            for type in writeTypes {
                _ = try? await store.deleteObjects(of: type, predicate: predicate)
            }
        }
        return wanted
    }
}
