import SwiftUI
import HealthCore

/// The after-exam check-in (H-B7): "How did it go?" after each of her exams,
/// two taps. Over a semester it shows how exams went after a full night
/// against a short one: her own small experiment, shown only once about 8
/// exams make it worth reading.
extension AppModel {
    typealias Felt = SleepExtrasData.ExamReflection.Felt

    /// Rated exams before the comparison shows.
    static let reflectionsNeeded = 8
    /// The check-in is offered for a week after the exam.
    static let reflectionDays = 7

    /// Her most recent exam that finished at least an hour ago, in the last
    /// week, not yet answered or skipped.
    var examToReflectOn: AppData.Exam? {
        let cal = Calendar.current
        let x = store.data.sleepExtras
        let answered = Set(x.examReflections.map(\.id)).union(x.skippedReflections)
        let weekAgo = cal.date(byAdding: .day, value: -Self.reflectionDays, to: .now) ?? .distantPast
        return store.data.exams
            .filter { !answered.contains($0.id) }
            .filter { exam in
                let start = Clock.date(exam.start, relativeTo: cal.startOfDay(for: exam.date))
                return start.addingTimeInterval(3600) <= .now && start >= weekAgo
            }
            .max { $0.date < $1.date }
    }

    func saveReflection(_ felt: Felt, for exam: AppData.Exam) {
        let title = UpcomingExam(exam: exam).title
        store.data.sleepExtras.examReflections.append(
            .init(id: exam.id, title: title, examDay: Calendar.current.startOfDay(for: exam.date), felt: felt))
    }

    func skipReflection(for exam: AppData.Exam) {
        store.data.sleepExtras.skippedReflections.insert(exam.id)
    }

    struct ReflectionSplit: Hashable {
        var fullWell: Int, full: Int
        var shortWell: Int, short: Int
    }

    /// Rated exams that have a recorded night before them, split by whether
    /// that night met her sleep need, with how many "went well" in each.
    var reflectionSplit: ReflectionSplit {
        let cal = Calendar.current
        let need = sleepNeed.minutes
        var s = ReflectionSplit(fullWell: 0, full: 0, shortWell: 0, short: 0)
        for r in store.data.sleepExtras.examReflections {
            guard let night = nights.first(where: { cal.isDate($0.wakeDay, inSameDayAs: r.examDay) }) else { continue }
            let well = r.felt == .well ? 1 : 0
            if SleepNeedEstimator.metNeed(asleep: night.asleepMinutes, need: need) { s.full += 1; s.fullWell += well } else { s.short += 1; s.shortWell += well }
        }
        return s
    }
}

/// The check-in row (when an exam is waiting for one) and the semester's
/// result row, for a `RowCard`. Draws nothing before her first exam.
struct ExamReflectionRows: View {
    /// Ends with a `RowDivider` when it draws anything (rows follow it).
    var dividerAfter = false
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @State private var asking: AppData.Exam? = nil

    /// Whether there's a check-in waiting or a result to show.
    static func hasContent(_ model: AppModel) -> Bool {
        model.examToReflectOn != nil || !model.store.data.sleepExtras.examReflections.isEmpty
    }

    var body: some View {
        let rated = store.data.sleepExtras.examReflections.count
        if let exam = model.examToReflectOn {
            MetricRow(title: "How did \(UpcomingExam(exam: exam).title) go?", note: "Two taps, for your own sleep experiment",
                      systemImage: "checkmark.bubble.fill", accent: .yellow) { asking = exam }
                .bottomSheet(item: $asking, title: { "How did \(UpcomingExam(exam: $0).title) go?" }) { exam in
                    answerSheet(exam)
                }
            if rated > 0 { RowDivider() }
        }
        if rated > 0 {
            ExpandRow(title: "After your exams", summary: summary(rated),
                      systemImage: "graduationcap.circle.fill", accent: .indigo) {
                Text(detail(rated)).fixedSize(horizontal: false, vertical: true)
            }
        }
        if dividerAfter && Self.hasContent(model) { RowDivider() }
    }

    private func summary(_ rated: Int) -> String {
        let s = model.reflectionSplit
        guard rated >= AppModel.reflectionsNeeded, s.full > 0, s.short > 0 else {
            return "\(rated) of \(AppModel.reflectionsNeeded) exams rated"
        }
        return "Went well \(s.fullWell) of \(s.full) full nights, \(s.shortWell) of \(s.short) short"
    }

    private func detail(_ rated: Int) -> String {
        let s = model.reflectionSplit
        let intro = "After each exam you said how it went. This puts that next to the night before: a full night (your sleep need) or a short one."
        guard rated >= AppModel.reflectionsNeeded, s.full > 0, s.short > 0 else {
            return intro + " It\u{2019}s only worth reading after about \(AppModel.reflectionsNeeded) exams, with some of each kind of night, so it shows then."
        }
        return intro + " After a full night, \(s.fullWell) of \(s.full) exams went well. After a short night, \(s.shortWell) of \(s.short) did. These are a handful of your own exams, so treat it as a hint, not proof."
    }

    @ViewBuilder
    private func answerSheet(_ exam: AppData.Exam) -> some View {
        VStack(spacing: Space.m) {
            ForEach([AppModel.Felt.well, .okay, .rough], id: \.self) { felt in
                PrimaryButton(title: label(felt), accent: felt == .rough ? .coral : felt == .okay ? .indigo : .mint) {
                    withMotion(.commit) { model.saveReflection(felt, for: exam) }
                    asking = nil
                }
            }
            Button("Skip this one") {
                model.skipReflection(for: exam)
                asking = nil
            }
            .font(.bodyEmphasis)
            .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
        }
    }

    private func label(_ felt: AppModel.Felt) -> String {
        switch felt {
        case .well: "Went well"
        case .okay: "OK"
        case .rough: "Rough"
        }
    }
}
