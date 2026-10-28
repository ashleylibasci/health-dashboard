import Foundation

/// Finds exams among calendar events by their titles: "STAT 400 Midterm",
/// "Final exam – Bio", "Quiz 3". Words that mean the event is about an exam
/// but isn't one ("Midterm review session", "Final exam prep") rule it out.
public enum ExamDetector {
    /// Exam words, matched as whole words (plural too), any case.
    public static let examWords = ["exam", "midterm", "final", "quiz", "test"]
    /// Events about an exam that aren't one.
    public static let notExamWords = ["review", "prep", "study", "studying", "office hours", "practice", "tutoring",
                                      "test drive", "covid test"]

    public static func isExam(_ title: String) -> Bool {
        examWords.contains { has($0, in: title) } && !notExamWords.contains { has($0, in: title) }
    }

    /// The kind for the exam list: "Final", "Midterm", "Quiz", "Test" or "Exam".
    public static func kind(of title: String) -> String {
        for (word, kind) in [("final", "Final"), ("midterm", "Midterm"), ("quiz", "Quiz"), ("test", "Test")] where has(word, in: title) {
            return kind
        }
        return "Exam"
    }

    private static func has(_ word: String, in title: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return title.range(of: "\\b\(escaped)(?:s|es|zes)?\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
