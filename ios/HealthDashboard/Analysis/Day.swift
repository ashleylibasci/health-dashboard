import Foundation

/// Calendar dates as "YYYY-MM-DD" strings, the same keys the web dashboard uses.
/// Date math runs in UTC so a key never drifts across a daylight-saving change.
enum Day {
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static func parse(_ key: String) -> Date {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
    }

    private static func format(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// The local calendar date of `date` in `timeZone`.
    static func key(_ date: Date, in timeZone: TimeZone = .current) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        let d = c.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", d.year!, d.month!, d.day!)
    }

    static func shift(_ key: String, _ days: Int) -> String {
        format(utc.date(byAdding: .day, value: days, to: parse(key))!)
    }

    static func between(_ from: String, _ to: String) -> Int {
        utc.dateComponents([.day], from: parse(from), to: parse(to)).day!
    }

    /// 0 = Sunday … 6 = Saturday.
    static func weekday(_ key: String) -> Int {
        utc.component(.weekday, from: parse(key)) - 1
    }

    /// "Fri, Oct 16"
    static func short(_ key: String) -> String {
        let f = DateFormatter()
        f.timeZone = utc.timeZone
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: parse(key))
    }

    /// "Mon"
    static func weekdayName(_ key: String, long: Bool = false) -> String {
        let f = DateFormatter()
        f.timeZone = utc.timeZone
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = long ? "EEEE" : "EEE"
        return f.string(from: parse(key))
    }
}
