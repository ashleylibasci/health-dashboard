import SwiftUI
import HealthCore

/// Today's pill as one row (H-A1): "Pill 18 of 28 · Take at 9pm" with a
/// Taken button, or "Taken 8:52pm" with a tick. Combined pill only; shows
/// nothing when there's no pack to go by. Put it in a `RowCard` when
/// `model.pillToday != nil` (Cycle has one; Today places it next).
struct PillTodayRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmUndo = false

    var body: some View {
        if let pill = model.pillToday {
            let p = Palette(scheme: scheme)
            AdaptiveStack(spacing: Space.m, alignment: .center) {
                HStack(spacing: Space.m) {
                    RowIcon(systemImage: pill.taken != nil ? "checkmark" : "pills.fill", accent: pill.taken != nil ? .mint : .pink)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(title(pill)).font(.bodyEmphasis).foregroundStyle(p.primary)
                        Text(note(pill)).font(.secondary).foregroundStyle(p.secondary)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            .minimumScaleFactor(0.85)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                }
                trailing(pill)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, minHeight: Sizes.tallRow, alignment: .leading)
            .sensoryFeedback(trigger: pill.taken) { old, new in old == nil && new != nil ? .success : nil }
            .confirmationDialog("Mark pill \(pill.packDay) as not taken?", isPresented: $confirmUndo, titleVisibility: .visible) {
                Button("Not taken", role: .destructive) { model.unmarkPillTaken(on: pill.day) }
            }
        }
    }

    private func title(_ pill: AppModel.PillToday) -> String {
        guard pill.isPillDay else { return "\(model.packBreakName) \u{00B7} no pill today" }
        return pill.isNewPack ? "New pack \u{00B7} pill 1" : "Pill \(pill.packDay) of \(pill.packLength)"
    }

    private func note(_ pill: AppModel.PillToday) -> String {
        if let taken = pill.taken {
            let at = "Taken \(Clock.format(Clock.minutesOfDay(taken)))"
            return pill.takenFromHealth ? "\(at) \u{00B7} from Apple Health" : at
        }
        guard pill.isPillDay else {
            return model.nextPackStart.map { "New pack \(PackPosition.shortDate($0))" } ?? "New pack soon"
        }
        // Away from home, her home pill time on this clock (H-A11).
        let time = model.pillAwayFromHome
            ? "\(BodyLogStyle.shortTime(model.pillTimeHere)) here"
            : Clock.format(store.data.pillTime)
        let due = Clock.minutesOfDay(.now) >= model.pillTimeHere || !Calendar.current.isDateInToday(pill.day)
        if pill.isNewPack { return due ? "Due at \(time) \u{00B7} starting on time matters most" : "Take at \(time) \u{00B7} starting on time matters most" }
        return due ? "Due at \(time) \u{00B7} not taken yet" : "Take at \(time)"
    }

    @ViewBuilder
    private func trailing(_ pill: AppModel.PillToday) -> some View {
        if pill.taken != nil {
            if !pill.takenFromHealth {
                Button("Undo") { confirmUndo = true }
                    .font(.secondary).fontWeight(.semibold)
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minWidth: Sizes.minTap, minHeight: Sizes.minTap)
                    .accessibilityLabel("Undo Taken")
            }
        } else if pill.isPillDay {
            Button {
                withMotion(.commit) { model.markPillTaken() }
            } label: {
                Label("Taken", systemImage: "checkmark")
                    .font(.bodyEmphasis)
                    .foregroundStyle(scheme == .dark ? Color(hex: 0x2A0A1A) : .white)
                    .padding(.horizontal, Space.l)
                    .frame(minHeight: Sizes.minTap)
                    .background(scheme == .dark ? Accent.pink.fill(.dark) : Accent.pink.ink(.light), in: Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Mark pill \(pill.packDay) as taken")
        }
    }
}
