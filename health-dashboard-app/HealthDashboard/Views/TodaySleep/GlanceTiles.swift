import SwiftUI
import HealthCore

/// The tiles At a glance can show (D-P4). Only inside At a glance: the
/// cards above it stay as they are.
enum GlanceTile: String, CaseIterable, Identifiable {
    case sleepDebt, caffeine, water, stress, energy, pill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepDebt: return "Sleep debt"
        case .caffeine: return "Caffeine"
        case .water: return "Water"
        case .stress: return "Stress"
        case .energy: return "Energy now"
        case .pill: return "Pill"
        }
    }

    var systemImage: String {
        switch self {
        case .sleepDebt: return "moon.zzz.fill"
        case .caffeine: return "cup.and.saucer.fill"
        case .water: return "drop.fill"
        case .stress: return "waveform.path"
        case .energy: return "bolt.fill"
        case .pill: return "pills.fill"
        }
    }

    var accent: Accent {
        switch self {
        case .sleepDebt: return .purple
        case .caffeine: return .yellow
        case .water: return .blue
        case .stress: return .orange
        case .energy: return .mint
        case .pill: return .pink
        }
    }

    /// The automatic four, in the morning order.
    static let automatic: [GlanceTile] = [.sleepDebt, .caffeine, .water, .stress]
}

extension AppModel {
    /// Her pinned tiles in her order, or nil for the automatic ones. The
    /// pill tile only while there's a pack to show.
    var pinnedGlanceTiles: [GlanceTile]? {
        guard let saved = store.data.insights.glanceTiles else { return nil }
        let tiles = saved.compactMap(GlanceTile.init(rawValue:))
        return tiles.filter { $0 != .pill || pillToday != nil }
    }
}

/// Edit At a glance (D-P4): drag to reorder, remove, add Pill or Energy;
/// or go back to the automatic tiles that follow the time of day.
struct GlanceTilesEditor: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var shown: [GlanceTile] = []
    @State private var loaded = false

    private var available: [GlanceTile] {
        GlanceTile.allCases.filter { !shown.contains($0) && ($0 != .pill || model.pillToday != nil) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shown) { tile in
                        row(tile) {
                            Button {
                                withMotion(.select) { shown.removeAll { $0 == tile } }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.scaled(size: 20))
                                    .foregroundStyle(Accent.coral.ink(scheme))
                                    .frame(width: Sizes.minTap, height: Sizes.minTap)
                            }
                            .buttonStyle(.plain)
                            .disabled(shown.count <= 1)
                            .accessibilityLabel("Remove \(tile.title)")
                        }
                    }
                    .onMove { from, to in shown.move(fromOffsets: from, toOffset: to) }
                } header: {
                    Text("Shown")
                } footer: {
                    Text("Drag to change the order.")
                }
                if !available.isEmpty {
                    Section("More tiles") {
                        ForEach(available) { tile in
                            row(tile) {
                                Button {
                                    withMotion(.select) { shown.append(tile) }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.scaled(size: 20))
                                        .foregroundStyle(Accent.mint.ink(scheme))
                                        .frame(width: Sizes.minTap, height: Sizes.minTap)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add \(tile.title)")
                            }
                        }
                    }
                }
                Section {
                    Button("Follow the time of day") {
                        store.data.insights.glanceTiles = nil
                        dismiss()
                    }
                    .disabled(store.data.insights.glanceTiles == nil)
                } footer: {
                    Text("The automatic tiles: stress in the morning, energy now from noon, caffeine first in the afternoon.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("At a glance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.data.insights.glanceTiles = shown.map(\.rawValue)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                shown = model.pinnedGlanceTiles ?? GlanceTile.automatic
            }
        }
    }

    private func row<Trailing: View>(_ tile: GlanceTile, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Space.m) {
            RowIcon(systemImage: tile.systemImage, accent: tile.accent)
            Text(tile.title).font(.bodyEmphasis)
            Spacer(minLength: Space.s)
            trailing()
        }
    }
}
