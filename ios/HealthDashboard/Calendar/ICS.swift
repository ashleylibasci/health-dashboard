import Foundation

struct CalendarEvent: Equatable {
    var title: String
    /// Local calendar date the event starts on, YYYY-MM-DD.
    var date: String
    /// Local start time as minutes after midnight, or nil for all-day events.
    var minutes: Int?
}

/// Words in an event title that mark it as an exam. Matched as whole words, any case.
let examWords = ["exam", "midterm", "final", "quiz"]

func isExam(_ title: String, words: [String] = examWords) -> Bool {
    words.contains { title.range(of: "\\b\($0)s?\\b", options: [.regularExpression, .caseInsensitive]) != nil }
}

/// Reads the events out of an iCalendar (.ics) feed, the format behind Google Calendar's
/// "secret address". Only one-off events: repeating ones (classes, office hours) are skipped,
/// since exams are almost never set up as repeats.
func parseICS(_ text: String, timeZone: TimeZone = .current) -> [CalendarEvent] {
    // Long lines are folded onto the next line with a leading space; join them back.
    let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
    var events: [CalendarEvent] = []
    var title: String?, start: String?, params = "", repeats = false, cancelled = false, inEvent = false

    for line in unfolded.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
        if line == "BEGIN:VEVENT" {
            inEvent = true
            title = nil; start = nil; params = ""; repeats = false; cancelled = false
        } else if line == "END:VEVENT" {
            if let t = title, let s = start, !repeats, !cancelled, let when = parseStart(s, params, timeZone) {
                events.append(CalendarEvent(title: t, date: when.date, minutes: when.minutes))
            }
            inEvent = false
        } else if inEvent, let colon = line.firstIndex(of: ":") {
            let head = line[..<colon].split(separator: ";").map(String.init)
            let value = String(line[line.index(after: colon)...])
            switch head.first {
            case "SUMMARY": title = unescapeICS(value)
            case "DTSTART": start = value; params = head.dropFirst().joined(separator: ";")
            case "RRULE": repeats = true
            case "STATUS": cancelled = value == "CANCELLED"
            default: break
            }
        }
    }
    return events.sorted { ($0.date, $0.minutes ?? -1) < ($1.date, $1.minutes ?? -1) }
}

private func parseStart(_ value: String, _ params: String, _ zone: TimeZone) -> (date: String, minutes: Int?)? {
    let digits = value.filter(\.isNumber)
    guard digits.count >= 8 else { return nil }
    let y = digits.prefix(4), mo = digits.dropFirst(4).prefix(2), d = digits.dropFirst(6).prefix(2)
    let date = "\(y)-\(mo)-\(d)"
    guard value.contains("T"), digits.count >= 12, !params.contains("VALUE=DATE") else { return (date, nil) }
    let h = Int(digits.dropFirst(8).prefix(2))!, mi = Int(digits.dropFirst(10).prefix(2))!
    if value.hasSuffix("Z") {
        // UTC time: show it in the phone's time zone.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = utc.date(from: DateComponents(year: Int(y), month: Int(mo), day: Int(d), hour: h, minute: mi))!
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let c = local.dateComponents([.hour, .minute], from: instant)
        return (Day.key(instant, in: zone), c.hour! * 60 + c.minute!)
    }
    // Floating or TZID time: already the wall-clock time where the event happens.
    return (date, h * 60 + mi)
}

private func unescapeICS(_ s: String) -> String {
    s.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\N", with: " ")
        .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
        .replacingOccurrences(of: "\\\\", with: "\\")
}
