import Foundation
import HealthCore

/// Her logs as one spreadsheet (G4), for a stats class or her own project:
/// one row per entry with the date, time, what it is, the number and its
/// unit. Sleep comes from Apple Health (left out on example data); the rest
/// is what she logged here.
extension AppModel {
    static let csvHeader = "date,time,type,value,unit,detail"

    func logsCSV() -> String {
        var rows: [(Date, String)] = []
        func row(_ date: Date, _ type: String, _ value: String, _ unit: String, _ detail: String = "") {
            let fields = [Self.csvDay.string(from: date), Self.csvTime.string(from: date), type, value, unit, detail].map(Self.csvField)
            rows.append((date, fields.joined(separator: ",")))
        }
        if !usingSampleData {
            for n in nights {
                let wake = AppDay.date(n.wake, relativeTo: n.wakeDay)
                row(wake, "sleep", "\(n.asleepMinutes)", "minutes asleep",
                    "bed \(Clock.format(n.bedtime)), woke \(Clock.format(n.wake))")
            }
        }
        for d in store.data.drinkLog { row(d.date, "caffeine", "\(d.mg)", "mg", d.name) }
        for w in store.data.waterLog { row(w.date, "water", String(format: "%.1f", w.ml / 29.5735), "oz") }
        for a in store.data.alcoholLog { row(a.date, "alcohol", String(format: "%.1f", a.standardDrinks), "standard drinks", a.phrase) }
        for c in store.data.checkIns { row(c.date, "check-in", "\(c.awake)", "awake 1-5", c.tags.joined(separator: "; ")) }
        for m in store.data.moodLog { row(m.date, "stress", "\(m.stress)", "1-5") }
        for r in store.data.moodRatings {
            row(r.date, r.scale.rawValue, "\(r.value)", r.scale == .mood ? "1 very low - 5 very good" : "1 none - 5 a lot")
        }
        return ([Self.csvHeader] + rows.sorted { $0.0 < $1.0 }.map(\.1)).joined(separator: "\n") + "\n"
    }

    /// The spreadsheet as a file to share; nil if it couldn't be written.
    func writeLogsCSV() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Health Dashboard logs.csv")
        do {
            let csv = logsCSV()
            try csv.write(to: url, atomically: true, encoding: .utf8)
            // Demo data: a copy in Documents, for the preview.
            if DemoMode.isOn, let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? csv.write(to: docs.appendingPathComponent("logs.csv"), atomically: true, encoding: .utf8)
            }
            return url
        } catch {
            return nil
        }
    }

    /// 2026-10-28 and 21:05, the way spreadsheets read them.
    private static let csvDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let csvTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Quotes a field when it holds a comma, quote or line break.
    static func csvField(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
