import SwiftUI

struct ExamsView: View {
    @Environment(AppModel.self) private var model
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exams").font(.serifTitle(34)).foregroundStyle(Color.ink)
            switch model.calendarState {
            case .notConnected:
                Card {
                    CardLabel("Connect Google Calendar")
                    Text("Add your calendar’s private link once, and the app checks for exams every time it opens and every 30 minutes while it’s open.")
                        .font(.system(size: 15)).foregroundStyle(Color.ink)
                    Button("Add calendar link") { showSettings = true }
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(Color.ink, in: Capsule())
                }
            case .loading:
                Card { ProgressView("Checking your calendar…").frame(maxWidth: .infinity) }
            case .failed(let message):
                Card {
                    Note(message)
                    Button("Check the link") { showSettings = true }.fontWeight(.bold)
                }
            case .ready(let checkedAt):
                upcoming
                lens
                Note("Calendar checked at \(checkedAt.formatted(date: .omitted, time: .shortened)). Events with exam, midterm, final or quiz in the title count.")
            }
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await model.refreshCalendar() }
    }

    private var upcoming: some View {
        Card {
            CardLabel("Next 3 weeks")
            if model.upcomingExams.isEmpty {
                Note("No exams in the next 3 weeks.")
            }
            ForEach(Array(model.upcomingExams.prefix(6).enumerated()), id: \.offset) { i, e in
                if i > 0 { Divider() }
                let d = Day.between(Day.key(.now), e.date)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                        Text(Day.short(e.date) + (e.minutes.map { " · " + clockOfDay($0) } ?? "")).font(.system(size: 13)).foregroundStyle(Color.muted)
                    }
                    Spacer()
                    Pill(text: d == 0 ? "Today" : d == 1 ? "Tomorrow" : "In \(d) days", fill: d <= 3 ? .peach : .lavender, ink: d <= 3 ? .peachInk : .mainText)
                }
            }
        }
    }

    @ViewBuilder private var lens: some View {
        if let l = model.examLens {
            Card(fill: .lavender) {
                CardLabel("Exam weeks vs. normal weeks")
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        Text("Exam weeks").fontWeight(.bold).foregroundStyle(Color.muted)
                        Text("Normal").fontWeight(.bold).foregroundStyle(Color.muted)
                    }
                    lensRow("Sleep", hoursMinutes(l.examWeeks.asleepMinutes), hoursMinutes(l.normalWeeks.asleepMinutes))
                    lensRow("Asleep at", clockTime(l.examWeeks.bedtime), clockTime(l.normalWeeks.bedtime))
                    lensRow("Resting HR", value(l.examWeeks.restingHr, " bpm"), value(l.normalWeeks.restingHr, " bpm"))
                    lensRow("HRV", value(l.examWeeks.hrv, " ms"), value(l.normalWeeks.hrv, " ms"))
                }
                .font(.system(size: 14))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Note("“Exam week” means the 6 nights before each exam. Based on \(l.exams) exams on your calendar in the last year: \(l.examWeeks.nights) exam-week nights vs. \(l.normalWeeks.nights) other nights.")
            }
        } else {
            Card(fill: .lavender) {
                CardLabel("Exam weeks vs. normal weeks")
                Note("Appears once your calendar has past exams that overlap your sleep data (at least 5 nights in exam weeks).")
            }
        }
    }

    private func lensRow(_ label: String, _ exam: String, _ normal: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Color.ink)
            Text(exam).fontWeight(.bold).foregroundStyle(Color.ink)
            Text(normal).fontWeight(.bold).foregroundStyle(Color.ink)
        }
    }

    private func value(_ v: Double?, _ unit: String) -> String {
        v.map { "\(Int($0.rounded()))\(unit)" } ?? "no data"
    }
}
