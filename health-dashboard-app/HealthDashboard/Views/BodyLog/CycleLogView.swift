import SwiftUI
import HealthCore

/// Log bleeding and symptoms for today or a past day. One entry per day:
/// saving a day again replaces what was there. Bleeding days update the
/// cycle day as soon as they're saved (the model recomputes on any change).
struct CycleLogView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var date = Date.now
    @State private var flow: AppData.Flow? = nil
    @State private var symptoms: Set<String> = []
    @State private var savedAt: Date? = nil
    @State private var confirmDelete: Date? = nil
    /// A day she picked while the shown day had unsaved changes.
    @State private var pendingDate: Date? = nil

    static let symptomOptions = ["Cramps", "Headache", "Bloating", "Acne", "Tender breasts",
                                 "Mood swings", "Fatigue", "Cravings", "Back pain", "Nausea"]

    private var options: [String] {
        var list = Self.symptomOptions
        if store.data.conditions.contains("PCOS") { list.append("Hair changes") }
        // Keep anything already logged that isn't in the list (e.g. from the Sick screen).
        for s in symptoms.sorted() where !list.contains(s) { list.append(s) }
        return list
    }

    private var cal: Calendar { Calendar.current }

    var body: some View {
        Screen(title: "Log", accent: .coral) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bleeding & symptoms").font(.scaled(size: 28, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text(introText).font(.scaled(size: 15)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            if model.usingSampleData {
                Text("The other numbers in the app are examples for now. What you log here is saved and counts toward your cycle right away.")
                    .font(.scaled(size: 13)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            PackCheckCard()
            dateCard
            flowCard
            symptomsCard
            PrimaryButton(title: saveTitle, accent: .coral, done: justSaved) { save() }
            recentSection
        }
        .onAppear { load() }
        .onChange(of: date) { load() }
        .task(id: savedAt) {
            // "Saved" shows for 2 seconds, then the button goes back to normal.
            guard savedAt != nil else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            savedAt = nil
        }
        .confirmationDialog("Save changes first?", isPresented: switchBinding, titleVisibility: .visible) {
            Button("Save \(date.formatted(.dateTime.month(.abbreviated).day()))") {
                save()
                if let d = pendingDate { date = d }
                pendingDate = nil
            }
            Button("Discard changes", role: .destructive) {
                if let d = pendingDate { date = d }
                pendingDate = nil
            }
            Button("Keep editing", role: .cancel) { pendingDate = nil }
        } message: {
            Text("You changed \(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) but haven\u{2019}t saved it.")
        }
        .confirmationDialog("Delete this day's log?", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let d = confirmDelete { delete(day: d) }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Removes bleeding and symptoms for that day.")
        }
    }

    private var introText: String {
        switch model.cycleDisplay {
        case .pack:
            return "On your method, the bleed in your break week is a withdrawal bleed, not a period. Logging it still helps you spot patterns."
        case .suppressed:
            return "Bleeding on your method may be light, irregular or absent. Logging it keeps a history you can show your doctor."
        default:
            return "Bleeding days set your cycle day. Pick a past date to fill in days you missed."
        }
    }

    // MARK: Date

    private var dateCard: some View {
        Card {
            DatePicker("Day", selection: dateBinding, in: ...Date.now, displayedComponents: .date)
                .font(.scaled(size: 15, weight: .bold))
                .tint(Accent.coral.ink(scheme))
                .frame(minHeight: 44)
            if hasEntry(on: date) {
                Label("Already logged. Saving replaces it.", systemImage: "pencil")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.coral.ink(scheme))
            }
        }
    }

    // MARK: Flow

    private var flowCard: some View {
        Card {
            HStack {
                SectionLabel(text: "Bleeding")
                Spacer()
                InfoButton(title: "Flow",
                           meaning: "How much you're bleeding today. Spotting is a few drops or brown discharge; light, medium and heavy are about how often you'd change a pad or tampon.",
                           forYou: flowForYou)
                    .padding(.vertical, -12)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(AppData.Flow.allCases, id: \.self) { f in
                    Chip(title: f.rawValue, selected: flow == f, accent: .coral) {
                        flow = flow == f ? nil : f
                    }
                }
            }
            if flow == .heavy {
                Text("Soaking through a pad or tampon every hour for several hours, or bleeding longer than 7 days, is worth a call to a doctor.")
                    .font(.scaled(size: 13))
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var flowForYou: String {
        if model.packMethod != nil {
            return "On your method a bleed in the break is a withdrawal bleed. Logging it keeps a history, and if bleeding comes well before your break the app asks you to check your pack day. It never moves your pack day by itself once you\u{2019}ve set it."
        }
        if model.ovulationStopped || store.birthControl == .hormonalIUD || store.birthControl == .miniPill {
            return "Logging bleeding and spotting keeps a history you can show your doctor. Bleeding on your method doesn\u{2019}t follow a monthly pattern, so it doesn\u{2019}t set phases or a countdown."
        }
        return "Logging the first heavy-ish day of bleeding tells the app when a new cycle started. Spotting doesn't start a new cycle."
    }

    // MARK: Symptoms

    private var symptomsCard: some View {
        Card {
            SectionLabel(text: "Symptoms")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(options, id: \.self) { s in
                    Chip(title: s, selected: symptoms.contains(s), accent: .purple) {
                        if symptoms.contains(s) { symptoms.remove(s) } else { symptoms.insert(s) }
                    }
                }
            }
        }
    }

    // MARK: Recent

    private struct DayLog: Identifiable {
        var id: Date { day }
        let day: Date
        let flow: AppData.Flow?
        let symptoms: [String]
    }

    private var recent: [DayLog] {
        let cutoff = cal.date(byAdding: .day, value: -60, to: cal.startOfDay(for: .now)) ?? .distantPast
        var days = Set<Date>()
        for e in store.data.flowLog where e.date >= cutoff { days.insert(cal.startOfDay(for: e.date)) }
        for e in store.data.symptomLog where e.date >= cutoff { days.insert(cal.startOfDay(for: e.date)) }
        return days.sorted(by: >).prefix(20).map { d in
            DayLog(day: d,
                   flow: store.data.flowLog.last { cal.isDate($0.date, inSameDayAs: d) }?.flow,
                   symptoms: store.data.symptomLog.last { cal.isDate($0.date, inSameDayAs: d) }?.symptoms ?? [])
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let items = recent
        SectionLabel(text: "Recent days").padding(.top, 6)
        if items.isEmpty {
            Card {
                Text("Nothing logged yet. Your days will show up here so you can edit or delete them.")
                    .font(.scaled(size: 14)).secondaryText()
            }
        } else {
            Card(padding: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Palette(scheme: scheme).cardBorder) }
                    recentRow(item)
                }
            }
        }
    }

    private func recentRow(_ item: DayLog) -> some View {
        let selected = cal.isDate(item.day, inSameDayAs: date)
        return HStack(spacing: 10) {
            Button { pick(item.day) } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.flow.map { $0 == .none ? "circle" : "drop.fill" } ?? "list.bullet")
                        .foregroundStyle(Accent.coral.ink(scheme))
                        .frame(width: 32, height: 32)
                        .background(Accent.coral.tint(scheme), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.scaled(size: 15, weight: .bold))
                        Text(summary(item)).font(.scaled(size: 13)).secondaryText()
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text(selected ? "Editing" : "Edit")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(Accent.indigo.ink(scheme))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(item.day.formatted(.dateTime.month(.wide).day())): \(summary(item))")
            Button { confirmDelete = item.day } label: {
                Image(systemName: "trash")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.pink.ink(scheme))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(item.day.formatted(.dateTime.month(.wide).day()))")
        }
    }

    private func summary(_ item: DayLog) -> String {
        var parts: [String] = []
        if let f = item.flow { parts.append(f.rawValue) }
        if !item.symptoms.isEmpty { parts.append(item.symptoms.joined(separator: ", ")) }
        return parts.isEmpty ? "Nothing logged" : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Saving

    /// Changing the day keeps unsaved edits: it asks first.
    private var dateBinding: Binding<Date> {
        Binding(get: { date }, set: { pick($0) })
    }

    private func pick(_ day: Date) {
        guard !cal.isDate(day, inSameDayAs: date) else { return }
        if isDirty { pendingDate = day } else { date = day }
    }

    private var switchBinding: Binding<Bool> {
        Binding(get: { pendingDate != nil }, set: { if !$0 { pendingDate = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
    }

    private var justSaved: Bool { savedAt != nil && !isDirty }

    private var isDirty: Bool {
        let f = store.data.flowLog.last { cal.isDate($0.date, inSameDayAs: date) }?.flow
        let s = Set(store.data.symptomLog.last { cal.isDate($0.date, inSameDayAs: date) }?.symptoms ?? [])
        return f != flow || s != symptoms
    }

    private var saveTitle: String {
        if justSaved { return "Saved" }
        return hasEntry(on: date) ? "Update this day" : "Save"
    }

    private func hasEntry(on day: Date) -> Bool {
        store.data.flowLog.contains { cal.isDate($0.date, inSameDayAs: day) }
            || store.data.symptomLog.contains { cal.isDate($0.date, inSameDayAs: day) }
    }

    private func load() {
        flow = store.data.flowLog.last { cal.isDate($0.date, inSameDayAs: date) }?.flow
        symptoms = Set(store.data.symptomLog.last { cal.isDate($0.date, inSameDayAs: date) }?.symptoms ?? [])
    }

    /// Noon on the chosen day, so time zones never push it into the next day.
    private var entryDate: Date {
        cal.isDateInToday(date) ? .now : (cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date)
    }

    private func save() {
        var data = store.data
        data.flowLog.removeAll { cal.isDate($0.date, inSameDayAs: date) }
        data.symptomLog.removeAll { cal.isDate($0.date, inSameDayAs: date) }
        if let flow { data.flowLog.append(.init(date: entryDate, flow: flow)) }
        let list = options.filter { symptoms.contains($0) }
        if !list.isEmpty { data.symptomLog.append(.init(date: entryDate, symptoms: list)) }
        data.flowLog.sort { $0.date < $1.date }
        data.symptomLog.sort { $0.date < $1.date }
        store.data = data
        savedAt = .now
    }

    private func delete(day: Date) {
        var data = store.data
        data.flowLog.removeAll { cal.isDate($0.date, inSameDayAs: day) }
        data.symptomLog.removeAll { cal.isDate($0.date, inSameDayAs: day) }
        store.data = data
        if cal.isDate(day, inSameDayAs: date) { load() }
    }
}
