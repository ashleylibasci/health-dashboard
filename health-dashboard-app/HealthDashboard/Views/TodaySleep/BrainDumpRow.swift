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

    private var text: Binding<String> {
        Binding(get: { store.data.sleepExtras.brainDump?.text ?? "" },
                set: { new in
                    let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.data.sleepExtras.brainDump = trimmed.isEmpty ? nil : .init(date: .now, text: new)
                })
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
            TextEditor(text: text)
                .focused($focused)
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
