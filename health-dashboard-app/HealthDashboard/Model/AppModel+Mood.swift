import Foundation
import HealthCore

/// Mood, anxiety and irritability, 1–5 each (B1): what she taps on the Log
/// tab, and mood by pack day on the combined pill.
extension AppModel {
    typealias MoodScale = AppData.MoodRating.Scale

    /// Each rating's app day (a tap at 1am counts for the evening before)
    /// → the latest value that day.
    func moodByDay(_ scale: MoodScale) -> [Date: Int] {
        var out: [Date: (at: Date, value: Int)] = [:]
        for r in store.data.moodRatings where r.scale == scale {
            let day = AppDay.day(containing: r.date)
            if let have = out[day], have.at > r.date { continue }
            out[day] = (r.date, r.value)
        }
        return out.mapValues(\.value)
    }

    /// Today's rating on each scale she's tapped.
    var moodToday: [MoodScale: Int] {
        var out: [MoodScale: Int] = [:]
        for r in store.data.moodRatings.sorted(by: { $0.date < $1.date }) where AppDay.contains(r.date) {
            out[r.scale] = r.value
        }
        return out
    }

    /// Saves one tap. Returns the entry (for Undo).
    @discardableResult
    func logMood(_ scale: MoodScale, _ value: Int, at date: Date = .now, id: UUID = UUID()) -> AppData.MoodRating {
        let entry = AppData.MoodRating(id: id, date: date, scale: scale, value: min(max(value, 1), 5))
        store.data.moodRatings.append(entry)
        return entry
    }

    func removeMood(_ id: UUID) {
        store.data.moodRatings.removeAll { $0.id == id }
    }

    /// Mood by pack day for one scale, since her last method change.
    func moodByPackDay(_ scale: MoodScale) -> MoodByPackDay? {
        guard let cal = packCalendar else { return nil }
        return MoodByPackDay.make(moodByDay(scale), in: cal, since: pillHistorySince)
    }

    /// "Very low" … "Very good" for mood; "None" … "A lot" for the others.
    static func moodWord(_ scale: MoodScale, _ value: Int) -> String {
        let words = scale == .mood
            ? ["Very low", "Low", "Okay", "Good", "Very good"]
            : ["None", "A little", "Some", "Quite a bit", "A lot"]
        return words[min(max(value, 1), 5) - 1]
    }

    static func moodTitle(_ scale: MoodScale) -> String {
        switch scale {
        case .mood: "Mood"
        case .anxiety: "Anxiety"
        case .irritability: "Irritability"
        }
    }
}
