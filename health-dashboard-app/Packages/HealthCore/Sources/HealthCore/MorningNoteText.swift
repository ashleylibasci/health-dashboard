import Foundation

/// The morning note's words and timing (D-N1): "68 · Take it steady" on
/// top, "Pill day 18 · bed by 11:50pm tonight" underneath, about 45
/// minutes after she wakes.
public enum MorningNoteText {
    /// Minutes after waking.
    public static let lead = 45
    /// No note once she's been up this long: it's no longer morning news.
    public static let latest = 180

    /// `score`/`label`: today's recovery, nil when the note is set before
    /// her sleep is in. `pillDay`: on a pill day. `bedtime`: minutes
    /// relative to the wake day. The pill is named only when the body is
    /// hidden on the lock screen (H-A5); the title never names it.
    public static func words(score: Int?, label: String?, pillDay: Int?, bedtime: Minutes,
                             bodyHiddenWhenLocked: Bool) -> (title: String, body: String) {
        let title = score.map { s in label.map { "\(s) \u{00B7} \($0)" } ?? "Recovery \(s)" } ?? "Good morning"
        var parts: [String] = []
        if let pillDay, bodyHiddenWhenLocked { parts.append("Pill day \(pillDay)") }
        parts.append("bed by \(Clock.format(bedtime)) tonight")
        let body = parts.joined(separator: " \u{00B7} ")
        return (title, body.prefix(1).uppercased() + body.dropFirst())
    }

    /// When the note for a morning she woke at `wake` goes out: 45 minutes
    /// later, or in a minute if that's past; nil once she's been up 3 hours.
    public static func fireDate(wake: Date, now: Date = .now) -> Date? {
        let fire = wake.addingTimeInterval(Double(lead * 60))
        if fire > now { return fire }
        guard now < wake.addingTimeInterval(Double(latest * 60)) else { return nil }
        return now.addingTimeInterval(60)
    }
}
