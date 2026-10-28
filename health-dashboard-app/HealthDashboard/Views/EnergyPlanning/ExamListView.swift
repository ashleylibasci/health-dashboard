import SwiftUI
import HealthCore

/// An upcoming exam as the exam screens show it: one she added
/// (`store.data.exams`), or an example while the app is on example data.
struct UpcomingExam: Identifiable, Hashable {
    var id: String
    /// "STAT 400"
    var course: String
    /// "Quiz", "Midterm"
    var kind: String
    var daysUntil: Int
    /// Start time, minutes after midnight on exam day.
    var start: Minutes
    var date: Date
    var isExample = false

    /// "STAT 400 quiz"
    var title: String {
        let k = kind.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return course }
        guard !course.lowercased().contains(k.lowercased()) else { return course }
        return "\(course) \(k.lowercased())"
    }

    init(id: String, course: String, kind: String, daysUntil: Int, start: Minutes, date: Date, isExample: Bool = false) {
        self.id = id
        self.course = course
        self.kind = kind
        self.daysUntil = daysUntil
        self.start = start
        self.date = date
        self.isExample = isExample
    }

    /// `today` defaults to the app day (at 1am it's still the evening before).
    init(exam: AppData.Exam, today: Date = AppDay.day(), calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: exam.date)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let name = exam.title.trimmingCharacters(in: .whitespaces)
        self.init(id: exam.id.uuidString, course: name.isEmpty ? "Exam" : name, kind: exam.kind,
                  daysUntil: max(days, 0), start: exam.start, date: day)
    }

    /// Example exams, only shown while the app is on example data and she
    /// hasn't added any: a quiz on the coming Thursday at 9:00am and a
    /// midterm in two weeks at 11:00am.
    static func samples(today: Date = .now, calendar: Calendar = .current) -> [UpcomingExam] {
        let day0 = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: day0)   // 1 = Sunday, 5 = Thursday
        var toThursday = (5 - weekday + 7) % 7
        if toThursday == 0 { toThursday = 7 }
        func make(_ course: String, _ kind: String, _ days: Int, _ start: Minutes) -> UpcomingExam {
            UpcomingExam(id: "example-\(course)", course: course, kind: kind, daysUntil: days, start: start,
                         date: calendar.date(byAdding: .day, value: days, to: day0) ?? day0, isExample: true)
        }
        return [make("STAT 400", "Quiz", toThursday, 540), make("ECON 201", "Midterm", 14, 660)]
    }
}

/// Her exams: add, change or remove them. The exam screens and the Today
/// chip use this list.
struct ExamListView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var editing: ExamDraft? = nil
    /// An exam she just saved that's within 10 days, while exam-week mode
    /// is off: the list offers to turn it on, right here (Whitfield F9).
    @State private var offer: AppData.Exam? = nil

    /// Counted from the app day, like `upcomingExams` (at 1am it's still the evening before).
    private var upcoming: [AppData.Exam] {
        let today = AppDay.day()
        return store.data.exams.filter { Calendar.current.startOfDay(for: $0.date) >= today }
            .sorted { ($0.date, $0.start) < ($1.date, $1.start) }
    }

    private var past: [AppData.Exam] {
        let today = AppDay.day()
        return store.data.exams.filter { Calendar.current.startOfDay(for: $0.date) < today }
    }

    var body: some View {
        Screen(title: "Your exams", accent: .yellow) {
            Text("Add your exams and the app plans your sleep, study blocks and exam-morning alarm around them. They stay on your phone.")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            if let offer {
                examModeOffer(offer)
                    .motionTransition(.reveal, edge: .top)
            }
            if upcoming.isEmpty {
                Card {
                    Text("No exams yet").font(.cardTitle)
                    Text("Add one below and the exam week screen and exam mode plan around it.")
                        .font(.bodyText).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Card(density: .compact) {
                    ForEach(upcoming) { exam in
                        ExamListRow(exam: UpcomingExam(exam: exam)) { editing = ExamDraft(exam) }
                        if exam.id != upcoming.last?.id { Divider() }
                    }
                }
            }
            PrimaryButton(title: "Add an exam", accent: .yellow) { editing = ExamDraft(nil) }
            CalendarImportCard()
            if !past.isEmpty {
                Button {
                    let today = AppDay.day()
                    store.data.exams.removeAll { Calendar.current.startOfDay(for: $0.date) < today }
                } label: {
                    Text(past.count == 1 ? "Remove 1 past exam" : "Remove \(past.count) past exams")
                        .font(.bodyEmphasis)
                        .foregroundStyle(Accent.coral.ink(scheme))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $editing) { draft in
            ExamEditorSheet(draft: draft) { saved in
                let days = Calendar.current.dateComponents([.day], from: AppDay.day(), to: saved.date).day ?? 99
                if !store.data.examModeOn, (0...10).contains(days) {
                    withMotion(.reveal) { offer = saved }
                }
            }
        }
        .motion(.reveal, value: offer?.id)
    }

    private func examModeOffer(_ exam: AppData.Exam) -> some View {
        Card(accent: .yellow) {
            if store.data.examModeOn {
                Label("Exam-week mode is on", systemImage: "checkmark.circle.fill")
                    .font(.cardTitle)
                    .foregroundStyle(Accent.yellow.onTint(scheme))
                LinkRow(title: "Open exam-week mode", subtitle: "Sleep, study blocks and an exam-morning alarm",
                        systemImage: "graduationcap.fill", accent: .yellow) {
                    ExamModeView()
                }
            } else {
                Text("Turn on exam-week mode?").font(.cardTitle).accessibilityAddTraits(.isHeader)
                Text("\(exam.title) is \(Self.when(exam.date)). Exam-week mode plans your sleep, study blocks and exam-morning alarm around it.")
                    .font(.bodyText).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Turn it on", accent: .yellow) {
                    withMotion(.reveal) { store.data.examModeOn = true }
                }
                Button("Not now") { withMotion(.reveal) { offer = nil } }
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
            }
        }
    }

    /// "today", "tomorrow", "on Thursday".
    private static func when(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: AppDay.day()) { return "today" }
        if let t = cal.date(byAdding: .day, value: 1, to: AppDay.day()), cal.isDate(date, inSameDayAs: t) { return "tomorrow" }
        return "on " + date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// The exam being added or changed.
struct ExamDraft: Identifiable {
    var id: UUID
    var isNew: Bool
    var title: String
    var kind: String
    var date: Date
    var time: Date

    init(_ exam: AppData.Exam?) {
        let cal = Calendar.current
        if let exam {
            id = exam.id
            isNew = false
            title = exam.title
            kind = exam.kind
            date = exam.date
            time = Clock.date(exam.start, relativeTo: cal.startOfDay(for: exam.date))
        } else {
            id = UUID()
            isNew = true
            title = ""
            kind = "Midterm"
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
            date = tomorrow
            time = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }
}

private struct ExamEditorSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State var draft: ExamDraft
    var onSaved: (AppData.Exam) -> Void = { _ in }

    private let kinds = ["Quiz", "Test", "Midterm", "Final", "Exam"]

    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let p = Palette(scheme: scheme)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Card {
                        SectionLabel(text: "Class or name")
                        TextField("e.g. STAT 400", text: $draft.title)
                            .font(.cardTitle)
                            .frame(minHeight: 44)
                        SectionLabel(text: "Kind")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) { kindChips }
                            VStack(spacing: 6) { kindChips }
                        }
                    }
                    Card {
                        DatePicker("Day", selection: $draft.date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                            .frame(minHeight: 44)
                        DatePicker("Starts at", selection: $draft.time, displayedComponents: .hourAndMinute)
                            .frame(minHeight: 44)
                    }
                    if !draft.isNew {
                        Button(role: .destructive) {
                            store.data.exams.removeAll { $0.id == draft.id }
                            dismiss()
                        } label: {
                            Text("Delete this exam")
                                .font(.bodyEmphasis)
                                .foregroundStyle(Accent.coral.ink(scheme))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(p.background)
            .navigationTitle(draft.isNew ? "Add an exam" : "Change exam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder private var kindChips: some View {
        ForEach(kinds, id: \.self) { k in
            Chip(title: k, selected: draft.kind == k, accent: .yellow) { draft.kind = k }
        }
    }

    private func save() {
        let cal = Calendar.current
        let exam = AppData.Exam(id: draft.id, title: draft.title.trimmingCharacters(in: .whitespaces),
                                kind: draft.kind, date: cal.startOfDay(for: draft.date),
                                start: Clock.minutesOfDay(draft.time))
        if let i = store.data.exams.firstIndex(where: { $0.id == draft.id }) {
            var exam = exam
            // An imported exam she changed is hers now: calendar imports
            // won't overwrite it or add it again.
            if let s = store.data.exams[i].source {
                exam.source = s.hasPrefix("edited:") ? s : "edited:" + s
            }
            store.data.exams[i] = exam
        } else {
            store.data.exams.append(exam)
            onSaved(exam)
        }
        dismiss()
    }
}

private struct ExamListRow: View {
    var exam: UpcomingExam
    var edit: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var when: String {
        let day: String
        switch exam.daysUntil {
        case 0: day = "Today"
        case 1: day = "Tomorrow"
        default: day = exam.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return "\(day) at \(Clock.format(exam.start))"
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        Button(action: edit) {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(Accent.yellow.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exam.title).font(.bodyEmphasis)
                    Text(when).font(.secondary).foregroundStyle(p.secondary)
                }
                Spacer()
                Text("Edit").font(.bodyEmphasis).foregroundStyle(Accent.yellow.ink(scheme))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Change or delete this exam")
    }
}

/// A small "Example" tag for example exams.
struct ExamExampleTag: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text("Example")
            .font(.secondary).fontWeight(.bold)
            .foregroundStyle(Accent.yellow.ink(scheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Accent.yellow.tint(scheme), in: Capsule())
    }
}

/// "Find exams on your calendar": connect Apple or Google Calendar once, and
/// exams on it (events with exam, midterm, final, quiz or test in the title)
/// join the list and stay up to date. Also in Settings and onboarding.
struct CalendarImportCard: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var importer = CalendarImport.shared
    @Environment(\.colorScheme) private var scheme
    @State private var showLink = false
    @State private var link = ""

    var body: some View {
        Card {
            HStack(spacing: 0) {
                Text("From your calendar").font(.cardTitle)
                InfoButton(title: "Exams from your calendar",
                           meaning: "The app looks for events with exam, midterm, final, quiz or test in the title, from today to four months ahead. Repeating events like classes are skipped, and so are events like \u{201C}midterm review\u{201D}.",
                           forYou: "It only reads your calendar, never changes it, and your events stay on your phone. Exams you add or edit here are never overwritten.")
                    .padding(.vertical, -12)
            }
            if let source = importer.source, importer.needsSignIn {
                // Google's sign-in ran out: sign in again, or switch to the
                // calendar link, which doesn't expire.
                Text("Google signed you out, so new exams aren\u{2019}t coming in.").font(.bodyText).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                connectButton(source, systemImage: "arrow.clockwise", title: "Sign in to Google again")
                linkEntry
                Button("Stop using Google Calendar", role: .destructive) { importer.disconnect() }
                    .font(.bodyEmphasis)
                    .frame(minHeight: 44)
            } else if let source = importer.source {
                Text(status(source)).font(.bodyText).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Button(importer.working ? "Checking\u{2026}" : "Check now") {
                        Task { await importer.check(model: model, force: true) }
                    }
                    .disabled(importer.working)
                    Button("Stop", role: .destructive) { importer.disconnect() }
                }
                .font(.bodyEmphasis)
                .tint(Accent.indigo.ink(scheme))
                .frame(minHeight: 44)
            } else {
                Text("Connect a calendar and your exams join your exam list on their own.")
                    .font(.bodyText).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { buttons }
                    VStack(alignment: .leading, spacing: 10) { buttons }
                }
                linkEntry
            }
            if let error = importer.error, !importer.needsSignIn {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.secondary)
                    .foregroundStyle(Accent.coral.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        connectButton(.apple, systemImage: "calendar")
        connectButton(.google, systemImage: "globe")
    }

    /// The secret iCal address: for a Google Calendar when Google sign-in
    /// doesn't work, or a school calendar.
    @ViewBuilder
    private var linkEntry: some View {
        // Plain buttons in the accent ink: inside onboarding's card a tint
        // alone left them white, like body text (round 3).
        Button(showLink ? "Hide calendar link" : "Or paste a calendar link") {
            withAnimation { showLink.toggle() }
        }
        .buttonStyle(.plain)
        .font(.bodyEmphasis)
        .foregroundStyle(Accent.indigo.ink(scheme))
        .multilineTextAlignment(.leading)
        .frame(minHeight: 44)
        if showLink {
            SecureField("Secret address (https:// or webcal://)", text: $link)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.bodyText)
                .padding(12)
                .background(Accent.indigo.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            Button(importer.working ? "Checking\u{2026}" : "Use this link") {
                Task {
                    await importer.connectLink(link, model: model)
                    if importer.source == .link { link = ""; showLink = false }
                }
            }
            .buttonStyle(.plain)
            .font(.bodyEmphasis)
            .foregroundStyle(Accent.indigo.ink(scheme))
            .frame(minHeight: 44)
            .disabled(importer.working || link.trimmingCharacters(in: .whitespaces).isEmpty)
            Text("In Google Calendar on a computer: Settings \u{2192} your calendar \u{2192} \u{201C}Secret address in iCal format.\u{201D} Treat it like a password: it\u{2019}s kept in your phone\u{2019}s Keychain.")
                .font(.secondary).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connectButton(_ source: CalendarSource, systemImage: String, title: String? = nil) -> some View {
        Button {
            Task { await importer.connect(source, model: model) }
        } label: {
            Label(title ?? source.name, systemImage: systemImage)
                .font(.bodyEmphasis)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(Accent.indigo.tint(scheme), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Accent.indigo.ink(scheme))
        .disabled(importer.working)
    }

    private func status(_ source: CalendarSource) -> String {
        let imported = model.store.data.exams.filter { $0.source?.contains(source.rawValue + ":") == true }.count
        let checked = importer.lastChecked.map { " Last checked \($0.formatted(date: .omitted, time: .shortened).lowercased())." } ?? ""
        let found = imported == 1 ? "1 exam" : "\(imported) exams"
        return "Reading \(source.name): \(found) from it.\(checked)"
    }
}
