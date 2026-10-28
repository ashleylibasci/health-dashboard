import Foundation

/// Reads events from an iCalendar (.ics) feed, the format behind Google
/// Calendar's "secret address in iCal format" and most school calendars.
/// Only one-off events: repeating ones (classes, office hours) and cancelled
/// ones are skipped, since exams are almost never set up as repeats.
public enum ICSCalendar {
    public struct Event: Equatable, Sendable {
        /// The event's UID, or its title and day when the feed has none.
        public var id: String
        public var title: String
        /// The local calendar day it starts on.
        public var year: Int, month: Int, day: Int
        /// Local start, minutes after midnight; nil for all-day events.
        public var start: Minutes?

        public init(id: String, title: String, year: Int, month: Int, day: Int, start: Minutes?) {
            self.id = id; self.title = title; self.year = year; self.month = month; self.day = day; self.start = start
        }
    }

    public static func parse(_ text: String, timeZone: TimeZone = .current) -> [Event] {
        // Long lines are folded onto the next line with a leading space or tab.
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        var events: [Event] = []
        var title: String?, start: String?, params = "", uid: String?
        var repeats = false, cancelled = false, inEvent = false
        // Depth inside the event's own blocks: a reminder's VALARM has its own
        // SUMMARY ("Alarm notification"), which mustn't replace the title.
        var nested = 0

        for line in unfolded.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                nested = 0
                title = nil; start = nil; params = ""; uid = nil; repeats = false; cancelled = false
            } else if line == "END:VEVENT" {
                if let t = title, let s = start, !repeats, !cancelled, let when = parseStart(s, params, timeZone) {
                    let key = uid ?? "\(t)|\(when.year)-\(when.month)-\(when.day)"
                    events.append(Event(id: key, title: t, year: when.year, month: when.month, day: when.day, start: when.minutes))
                }
                inEvent = false
            } else if inEvent, line.hasPrefix("BEGIN:") {
                nested += 1
            } else if inEvent, line.hasPrefix("END:") {
                nested = max(0, nested - 1)
            } else if inEvent, nested == 0, let colon = line.firstIndex(of: ":") {
                let head = line[..<colon].split(separator: ";").map(String.init)
                let value = String(line[line.index(after: colon)...])
                switch head.first {
                case "SUMMARY": title = unescape(value)
                case "UID": uid = value
                case "DTSTART": start = value; params = head.dropFirst().joined(separator: ";")
                case "RRULE", "RECURRENCE-ID": repeats = true
                case "STATUS": cancelled = value == "CANCELLED"
                default: break
                }
            }
        }
        return events
    }

    private static func parseStart(_ value: String, _ params: String, _ zone: TimeZone) -> (year: Int, month: Int, day: Int, minutes: Minutes?)? {
        let digits = Array(value.filter(\.isNumber))
        guard digits.count >= 8,
              let y = Int(String(digits[0..<4])), let mo = Int(String(digits[4..<6])), let d = Int(String(digits[6..<8])) else { return nil }
        guard value.contains("T"), digits.count >= 12, !params.contains("VALUE=DATE"),
              let h = Int(String(digits[8..<10])), let mi = Int(String(digits[10..<12])) else { return (y, mo, d, nil) }
        if value.hasSuffix("Z") {
            // UTC: shown in the phone's time zone, which can change the day.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            guard let instant = utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)) else { return nil }
            var local = Calendar(identifier: .gregorian)
            local.timeZone = zone
            let c = local.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
            return (c.year ?? y, c.month ?? mo, c.day ?? d, (c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        // Floating or TZID time: already the wall-clock time where it happens.
        return (y, mo, d, h * 60 + mi)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
