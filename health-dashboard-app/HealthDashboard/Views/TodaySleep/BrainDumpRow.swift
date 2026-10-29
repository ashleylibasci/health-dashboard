import SwiftUI
import HealthCore

/// "Tomorrow's list" in tonight's wind-down (H-B4): an optional two-minute
/// to-do list before bed, so the next day's tasks are on paper instead of
/// on her mind. It stays on the phone and is cleared a week after she
/// last wrote in it (`AppModel.clearOldBrainDump`).
struct BrainDumpRow: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    /// Edited here and saved when she's done typing (saving every
    /// keystroke would redo the whole app's numbers each time).
    @State private var draft = ""

    private func save() {
        let saved = store.data.sleepExtras.brainDump?.text ?? ""
        guard draft != saved else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.data.sleepExtras.brainDump = trimmed.isEmpty ? nil : .init(date: .now, text: draft)
    }

    private var summary: String {
        guard let dump = store.data.sleepExtras.brainDump else { return "Two minutes, then let it go" }
        let items = dump.text.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return items == 1 ? "1 thing for tomorrow" : "\(items) things for tomorrow"
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        ExpandRow(title: "Tomorrow\u{2019}s list", summary: summary, systemImage: "list.bullet.clipboard", accent: .indigo) {
            Text("Writing down what\u{2019}s on for tomorrow helps you fall asleep faster. One thing per line.")
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $draft)
                .focused($focused)
                .onAppear { draft = store.data.sleepExtras.brainDump?.text ?? "" }
                .onChange(of: focused) { if !focused { save() } }
                .onDisappear { save() }
                .font(.bodyText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(Space.s)
                .background(p.chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .accessibilityLabel("Tomorrow's list")
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused = false }
                    }
                }
            Text("Stays on your phone and clears itself after a week.")
                .font(.secondary)
                .foregroundStyle(p.secondary)
        }
    }
}

extension AppModel {
    /// A list from tomorrow's-list is kept for a week after she last wrote in it.
    static let brainDumpDays = 7

    /// Clears tomorrow's list once it's a week old. Runs on every refresh.
    func clearOldBrainDump(now: Date = .now) {
        guard let dump = store.data.sleepExtras.brainDump,
              let expiry = Calendar.current.date(byAdding: .day, value: Self.brainDumpDays, to: dump.date),
              expiry <= now else { return }
        store.data.sleepExtras.brainDump = nil
    }
}
