import SwiftUI
import HealthCore

/// Add or remove health conditions. Each one changes what the app shows.
struct ConditionsView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    /// An eating-disorder history: removing it asks first.
    @State private var confirmRemove: String? = nil

    private static let confirmFirst: Set<String> = ["Eating-disorder history"]

    private var removeBinding: Binding<Bool> {
        Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })
    }

    private let removeMessage = "Calories, step counts, exercise targets and your water goal will show again in the app."

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
            .font(.detailTitle)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text("Optional. Each one says exactly what it changes in the app. Some are only saved for your own reference.")
                .font(.bodyText)
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)

            Label("Private and stays on your phone", systemImage: "lock.fill")
                .font(.secondary).fontWeight(.semibold)
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
                .font(.secondary)
                .secondaryText()
                .padding(.top, 4)
        }
        .animation(.easeInOut(duration: 0.2), value: store.data.conditions)
        .confirmationDialog("Remove \(confirmRemove ?? "")?", isPresented: removeBinding, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let name = confirmRemove { remove(name) }
                confirmRemove = nil
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
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(Accent.indigo.fill(scheme).opacity(0.24), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    // Wraps the tag under the name instead of breaking
                    // "Endometriosis" into letters at large sizes.
                    FlowLayout(spacing: 8, lineSpacing: 4) {
                        Text(item.name).font(.bodyEmphasis)
                        Text("Added")
                            .font(.small).fontWeight(.bold)
                            .foregroundStyle(Accent.indigo.ink(scheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Accent.indigo.fill(scheme).opacity(0.2), in: Capsule())
                    }
                    Text(item.change).font(.bodyText).secondaryText()
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
                    .font(.bodyEmphasis)
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
                Text(item.name).font(.bodyEmphasis)
                Text(item.change).font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                if item.name == "PCOS" {
                    NavigationLink { PCOSView() } label: {
                        Text("Learn about PCOS")
                            .font(.secondary).fontWeight(.semibold)
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
                    .font(.bodyEmphasis)
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
                .font(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: Self.anad) {
                Label("Call ANAD", systemImage: "phone.fill")
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Call the ANAD helpline, 1-888-375-7767")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Accent.indigo.fill(scheme).opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
    }
}
