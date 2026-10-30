import Foundation

/// What the sleep and exam features save (the bedtime nudge, after-exam
/// check-ins, the exam crunch). Kept in one field of
/// `AppData` so it stays on the phone with everything else. Decoding is
/// forgiving, like `AppData`'s.
struct SleepExtrasData: Codable, Hashable {
    /// How an exam went, from the two-tap check-in after it.
    struct ExamReflection: Codable, Hashable, Identifiable {
        enum Felt: Int, Codable, CaseIterable { case rough = 1, okay = 2, well = 3 }
        /// The exam's id (`AppData.Exam.id`), so it's asked once.
        var id: UUID
        var title: String
        /// The exam day (start of day), paired with the night before it.
        var examDay: Date
        var felt: Felt
    }

    /// "Lights low, screens down" 45 minutes before tonight's bedtime.
    var bedtimeNudge = false
    var examReflections: [ExamReflection] = []
    /// Exams she skipped the check-in for, so it isn't asked again.
    var skippedReflections: Set<UUID> = []
    /// The first exam day of a crunch week that already turned exam mode
    /// on, so turning it off again sticks.
    var crunchTurnedOn: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SleepExtrasData()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        bedtimeNudge = get(.bedtimeNudge, d.bedtimeNudge)
        examReflections = get(.examReflections, d.examReflections)
        skippedReflections = get(.skippedReflections, d.skippedReflections)
        crunchTurnedOn = get(.crunchTurnedOn, d.crunchTurnedOn)
    }
}
