import SwiftUI

// MARK: Confirmation toast

/// A short "Saved" or error message that fades out on its own, so a second save never looks like the first.
struct Toast: Equatable {
    var text: String
    var isError = false
    var stamp = Date.now
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                Label(toast.text, systemImage: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(toast.isError ? Color.peachInk : Color.mintInk)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(toast.isError ? Color.peach : Color.mint, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.horizontal, 20).padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.stamp) {
                        try? await Task.sleep(for: .seconds(toast.isError ? 5 : 2.5))
                        withAnimation { self.toast = nil }
                    }
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View { modifier(ToastModifier(toast: toast)) }
}

// MARK: When it happened

/// "Now" by default; "Earlier" opens a time picker for the last two days.
struct WhenPicker: View {
    @Binding var date: Date
    @Binding var custom: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("When").font(.subheadline.weight(.bold)).foregroundStyle(Color.muted)
                Chip(text: "Now", selected: !custom) { custom = false; date = .now }
                Chip(text: custom ? date.formatted(.dateTime.weekday(.abbreviated).hour().minute()) : "Earlier…", selected: custom) { custom = true }
            }
            if custom {
                DatePicker("Time", selection: $date, in: Date.now.addingTimeInterval(-2 * 86400)...Date.now, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .font(.subheadline)
            }
        }
    }
}

// MARK: Edit one day (periods, spotting, symptoms)

/// The one place period days are logged and fixed: open it from any calendar day or the Log tab.
/// It starts with what's already saved for that day, and Save replaces it.
struct DayLogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var day: String
    @State private var flow: Int?
    @State private var symptoms: Set<Symptom> = []
    @State private var saving = false
    @State private var error: String?

    private static let flows: [(Int, String)] = [(0, "None"), (1, "Spotting"), (2, "Light"), (3, "Medium"), (4, "Heavy")]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button { day = Day.shift(day, -1) } label: { Image(systemName: "chevron.left").font(.headline) }
                            .accessibilityLabel("Previous day")
                        Spacer()
                        VStack(spacing: 2) {
                            Text(dayTitle).font(.serifTitle(26)).foregroundStyle(Color.ink)
                            Text(Day.short(day)).font(.subheadline).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        Button { day = Day.shift(day, 1) } label: { Image(systemName: "chevron.right").font(.headline) }
                            .disabled(day >= model.today)
                            .accessibilityLabel("Next day")
                    }
                    .foregroundStyle(Color.mainText)

                    VStack(alignment: .leading, spacing: 10) {
                        CardLabel("Bleeding", color: .muted)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(Self.flows, id: \.0) { level, name in
                                Button { flow = flow == level ? nil : level } label: {
                                    VStack(spacing: 4) {
                                        FlowDrops(level: level)
                                        Text(name).font(.subheadline.weight(flow == level ? .bold : .semibold))
                                    }
                                    .foregroundStyle(Color.ink)
                                    .frame(maxWidth: .infinity, minHeight: 64)
                                    .background(flow == level ? Color.rose : Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(flow == level ? Color.peachInk : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(flow == level ? .isSelected : [])
                            }
                        }
                        Note(flowNote)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        CardLabel("Symptoms", color: .muted)
                        FlowLayout {
                            ForEach(Symptom.cycle) { s in
                                Chip(text: s.rawValue, selected: symptoms.contains(s)) {
                                    if symptoms.contains(s) { symptoms.remove(s) } else { symptoms.insert(s) }
                                }
                            }
                        }
                    }

                    if let error { Note(error) }

                    PrimaryButton(title: saving ? "Saving…" : "Save") { save(flow: flow, symptoms: symptoms) }
                        .disabled(saving)
                    if model.dayLog(day).flow != nil || !(model.dayLog(day).symptoms.isEmpty) {
                        Button("Clear this day", role: .destructive) { save(flow: nil, symptoms: []) }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .disabled(saving)
                    }
                    Note("Saved to Apple Health. Clearing removes what this app logged; anything added in the Health app itself stays there.")
                }
                .padding(20)
            }
            .background(Color.ground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear(perform: load)
            .onChange(of: day) { load() }
        }
    }

    private var dayTitle: String {
        let d = Day.between(day, model.today)
        return d == 0 ? "Today" : d == 1 ? "Yesterday" : Day.weekdayName(day, long: true)
    }

    private var flowNote: String {
        switch flow {
        case 1?: "Spotting is light bleeding between periods. It’s saved separately, so it doesn’t count as a period day."
        case 0?: "No bleeding today. Useful for marking that a period has ended."
        case let level? where level >= 2:
            startsNewPeriod(day, flow: model.health.flow.filter { $0.key != day }) ? "This will be day 1 of a new period." : "Part of the period already logged."
        default: "Tap a bleeding level, or leave it blank."
        }
    }

    private func load() {
        let saved = model.dayLog(day)
        flow = saved.flow
        symptoms = saved.symptoms
        error = nil
    }

    private func save(flow: Int?, symptoms: Set<Symptom>) {
        saving = true
        Task {
            let ok = await model.saveDay(day, flow: flow, symptoms: symptoms)
            saving = false
            if ok { dismiss() } else { error = "Couldn’t save to Apple Health: \(model.lastLogError ?? "unknown error")" }
        }
    }
}

/// Little drop icons for flow levels: none, a dot for spotting, one to three drops.
struct FlowDrops: View {
    var level: Int
    var body: some View {
        HStack(spacing: 2) {
            switch level {
            case 0: Image(systemName: "drop").foregroundStyle(Color.muted)
            case 1: Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(Color(hex: 0xF07A6B))
            case 2...4: ForEach(0..<(level - 1), id: \.self) { _ in Image(systemName: "drop.fill").foregroundStyle(Color(hex: 0xF07A6B)) }
            default: EmptyView() // nothing logged
            }
        }
        .font(.caption)
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

// MARK: Caffeine: see and fix today's logs

/// Tonight's caffeine logs (anything after 5am today, or last night if it's before 5am).
/// Tap one to change its time or amount, or delete it.
struct CaffeineLogList: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Reading?

    var body: some View {
        let logs = model.caffeineToday
        VStack(alignment: .leading, spacing: 8) {
            if logs.isEmpty {
                Note("Nothing logged yet today.")
            } else {
                ForEach(logs) { log in
                    Button { editing = log } label: {
                        HStack {
                            Image(systemName: "cup.and.saucer.fill").foregroundStyle(Color.butterInk)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(log.name ?? "Caffeine").font(.subheadline.weight(.bold)).foregroundStyle(Color.ink)
                                Text(log.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(Color.muted)
                            }
                            Spacer()
                            Text("\(Int(log.value)) mg").font(.subheadline.weight(.bold)).foregroundStyle(Color.ink)
                            Image(systemName: "pencil").font(.caption).foregroundStyle(Color.muted)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(log.name ?? "Caffeine"), \(Int(log.value)) milligrams at \(log.date.formatted(date: .omitted, time: .shortened)). Tap to change.")
                }
            }
        }
        .sheet(item: $editing) { log in CaffeineEditSheet(log: log) }
    }
}

struct CaffeineEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var log: Reading
    @State private var date = Date.now
    @State private var mg = 130.0
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                    Stepper(value: $mg, in: 5...600, step: 5) {
                        HStack { Text("Amount"); Spacer(); Text("\(Int(mg)) mg").fontWeight(.bold) }
                    }
                } header: {
                    Text(log.name ?? "Caffeine")
                } footer: {
                    if !log.mine {
                        Text("Logged by another app (like Shortcuts), so it can only be changed in the Health app: Health → Browse → Nutrition → Caffeine.")
                    }
                }
                if let error { Text(error).foregroundStyle(Color.peachInk) }
                Section {
                    Button("Delete this log", role: .destructive) {
                        run { await model.deleteCaffeine(log) }
                    }
                }
            }
            .disabled(saving || !log.mine)
            .navigationTitle("Change caffeine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { run { await model.editCaffeine(log, mg: mg, at: date) } }
                        .disabled(saving || !log.mine)
                }
            }
            .onAppear { date = log.date; mg = log.value }
        }
        .presentationDetents([.medium, .large])
    }

    private func run(_ work: @escaping () async -> Bool) {
        saving = true
        Task {
            let ok = await work()
            saving = false
            if ok { dismiss() } else { error = model.lastLogError }
        }
    }
}
