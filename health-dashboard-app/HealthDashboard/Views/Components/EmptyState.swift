import SwiftUI

/// What a screen shows when there's nothing to show yet (D-L2): one
/// friendly line and the one thing that fills it, never an empty chart
/// grid or a stack of "None yet" rows. "No nights yet" · Get set up.
struct EmptyStateCard<Destination: View>: View {
    var text: String
    var actionTitle: String
    var systemImage: String
    var accent: Accent
    var action: (() -> Void)?
    @ViewBuilder var destination: Destination
    @Environment(\.colorScheme) private var scheme

    init(_ text: String, actionTitle: String, systemImage: String, accent: Accent,
         @ViewBuilder destination: () -> Destination) {
        self.text = text
        self.actionTitle = actionTitle
        self.systemImage = systemImage
        self.accent = accent
        self.action = nil
        self.destination = destination()
    }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: systemImage)
                    .foregroundStyle(accent.ink(scheme))
                    .accessibilityHidden(true)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.bodyEmphasis)
            if let action {
                Button(action: action) { buttonLabel }
                    .buttonStyle(.pressable)
            } else {
                NavigationLink { destination } label: { buttonLabel }
                    .buttonStyle(.pressable)
            }
        }
    }

    private var buttonLabel: some View {
        Text(actionTitle)
            .font(.bodyEmphasis)
            .foregroundStyle(accent.ink(scheme))
            .padding(.horizontal, Space.l)
            .frame(minHeight: Sizes.minTap)
            .background(accent.tint(scheme), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.ink(scheme).opacity(0.25)))
    }
}

extension EmptyStateCard where Destination == EmptyView {
    /// The button runs `action` (switches tab, opens a sheet).
    init(_ text: String, actionTitle: String, systemImage: String, accent: Accent, action: @escaping () -> Void) {
        self.text = text
        self.actionTitle = actionTitle
        self.systemImage = systemImage
        self.accent = accent
        self.action = action
        self.destination = EmptyView()
    }
}
