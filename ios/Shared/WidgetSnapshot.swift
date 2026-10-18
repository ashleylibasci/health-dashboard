import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The handful of numbers the widgets show. The app writes it to the shared App Group
/// container each time it reads Health; the widgets only read it.
struct WidgetSnapshot: Codable, Equatable {
    var name: String = ""
    var recovery: Int?
    var recoveryLabel: String = ""
    var headline: String = "Open the app to get started"
    var cycleDay: Int?
    var phase: String?
    var sleepMinutes: Int?
    var bedBy: String?
    var energy: Int?
    var streakNights: Int = 0
    var caffeineMg: Double = 0
    var caffeineDay: String = ""
    var updated = Date.distantPast

    static let appGroup = "group.com.ashleylibasci.healthdashboard"
    private static let key = "widgetSnapshot.v1"

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Today's caffeine, reset to zero once the day changes.
    var caffeineToday: Double {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return caffeineDay == f.string(from: .now) ? caffeineMg : 0
    }
}
