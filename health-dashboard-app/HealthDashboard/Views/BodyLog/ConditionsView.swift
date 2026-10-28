import SwiftUI
import HealthCore

/// Add or remove health conditions. Each one changes what the app shows.
struct ConditionsView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    /// PMDD or an eating-disorder history: removing it asks first.
    @State private var confirmRemove: String? = nil
    @AppStorage("crisisLineCompact") private var crisisCompact = false

    private static let confirmFirst: Set<String> = ["PMDD", "Eating-disorder history"]

    private var removeBinding: Binding<Bool> {
        Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })
    }

    private var removeMessage: String {
        confirmRemove == "PMDD"
            ? "The 988 Lifeline will no longer show on the Body and Cycle screens. If it just takes up too much room, you can keep it as one line instead."
            : "Calories, step counts, exercise targets and your water goal will show again in the app."
    }

    private func remove(_ name: String) {
        store.data.conditions.removeAll { $0 == name }
    }

    private var added: [ConditionCatalog.Item] {
        ConditionCatalog.all.filter { store.data.conditions.contains($0.name) }
    }

    private var available: [ConditionCatalog.Item] {
        ConditionCatalog.all.filter { !store.data.conditions.contains($0.name) }
    }

    var body: some View {
        Screen(title: "Health conditions", accent: .purple) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Anything we")
                Text("should know?").foregroundStyle(Accent.indigo.ink(scheme))
            }
            .font(.scaled(size: 32, weight: .bold))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text("Optional. Each one says exactly what it changes in the app. Some are only saved for your own reference.")
                .font(.scaled(size: 16))
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)

            Label("Private and stays on your phone", systemImage: "lock.fill")
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(Accent.mint.ink(scheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Accent.mint.tint(scheme), in: Capsule())
                .overlay(Capsule().strokeBorder(Accent.mint.fill(scheme).opacity(0.2)))

            if !added.isEmpty {
                SectionLabel(text: "Added").padding(.top, 6)
                ForEach(added) { item in
                    addedCard(item)
                }
            }

            if !available.isEmpty {
                SectionLabel(text: added.isEmpty ? "Conditions you can add" : "More you can add").padding(.top, 6)
                Card(density: .compact) {
                    ForEach(Array(available.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Palette(scheme: scheme).cardBorder) }
                        availableRow(item)
                    }
                }
            }

            Text("General information, not medical advice. The app can\u{2019}t diagnose any condition.")
                .font(.scaled(size: 12))
                .secondaryText()
                .padding(.top, 4)
        }
        .animation(.easeInOut(duration: 0.2), value: store.data.conditions)
        .confirmationDialog("Remove \(confirmRemove ?? "")?", isPresented: removeBinding, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let name = confirmRemove { remove(name) }
                confirmRemove = nil
            }
            if confirmRemove == "PMDD" {
                Button("Keep it, show 988 as one line") {
                    crisisCompact = true
                    confirmRemove = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmRemove = nil }
        } message: {
            Text(removeMessage)
        }
    }

    // MARK: Rows

    private func addedCard(_ item: ConditionCatalog.Item) -> some View {
        Card(accent: .indigo) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.scaled(size: 14, weight: .heavy))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(width: 36, height: 36)
                    .background(Accent.indigo.fill(scheme).opacity(0.24), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    // Wraps the tag under the name instead of breaking
                    // "Endometriosis" into letters at large sizes.
                    FlowLayout(spacing: 8, lineSpacing: 4) {
                        Text(item.name).font(.scaled(size: 16, weight: .bold))
                        Text("Added")
                            .font(.scaled(size: 11, weight: .bold))
                            .foregroundStyle(Accent.indigo.ink(scheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Accent.indigo.fill(scheme).opacity(0.2), in: Capsule())
                    }
                    Text(item.change).font(.scaled(size: 14)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .overlay(alignment: .topTrailing) { info(item).offset(x: 10, y: -10) }

            if item.name == "Eating-disorder history" {
                EatingDisorderSupportRow()
            }

            if item.name == "PCOS" {
                LinkRow(title: "Living with PCOS", subtitle: "What changes, what to log, trusted info",
                        systemImage: "book.fill", accent: .indigo) {
                    PCOSView()
                }
            }

            Button(role: .destructive) {
                if Self.confirmFirst.contains(item.name) { confirmRemove = item.name } else { remove(item.name) }
            } label: {
                Text("Remove")
                    .font(.scaled(size: 14, weight: .semibold))
                    .foregroundStyle(Accent.pink.ink(scheme))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.name)")
        }
    }

    private func info(_ item: ConditionCatalog.Item) -> some View {
        InfoButton(title: item.name, meaning: item.meaning, forYou: "In this app: " + item.change)
    }

    private func availableRow(_ item: ConditionCatalog.Item) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.scaled(size: 15, weight: .bold))
                Text(item.change).font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                if item.name == "PCOS" {
                    NavigationLink { PCOSView() } label: {
                        Text("Learn about PCOS")
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(Accent.indigo.ink(scheme))
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .contain)
            Spacer(minLength: 0)
            info(item)
            Button {
                store.data.conditions.append(item.name)
            } label: {
                Text("Add")
                    .font(.scaled(size: 14, weight: .bold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .padding(.horizontal, 16)
                    .frame(minWidth: 60, minHeight: 44)
                    .background(Accent.indigo.fill(scheme).opacity(0.18), in: Capsule())
                    .overlay(Capsule().strokeBorder(Accent.indigo.fill(scheme).opacity(0.3)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(item.name)")
        }
        .padding(.vertical, 6)
    }
}

/// Where to get support with an eating disorder: the ANAD helpline (the
/// NEDA helpline closed in 2023) and campus counseling (Cole 6).
struct EatingDisorderSupportRow: View {
    @Environment(\.colorScheme) private var scheme
    private static let anad = URL(string: "tel:18883757767")!

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Support if you want it: the ANAD eating-disorder helpline is free, 1-888-375-7767 (US). Your campus counseling center can help too.")
                .font(.scaled(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: Self.anad) {
                Label("Call ANAD", systemImage: "phone.fill")
                    .font(.scaled(size: 14, weight: .bold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Call the ANAD helpline, 1-888-375-7767")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Accent.indigo.fill(scheme).opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
