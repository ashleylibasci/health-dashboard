import SwiftUI
import UIKit
import HealthCore

// Feedback for logging, shared by the Log tab and the Caffeine, Water,
// Alcohol, Cycle and check-in screens: a toast with Undo at the bottom of
// the screen (as on the Watch), a small "History" link, and clock times with
// a smaller am/pm.

/// What just got logged, and how to take it back.
struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    /// nil: nothing to undo (the toast is only a confirmation).
    var undo: (() -> Void)?

    init(_ message: String, undo: (() -> Void)? = nil) {
        self.message = message
        self.undo = undo
    }

    static func == (a: UndoToast, b: UndoToast) -> Bool { a.id == b.id }

    /// How long it stays: 5 seconds, longer with VoiceOver so there's time
    /// to reach Undo.
    static var duration: Double { UIAccessibility.isVoiceOverRunning ? 10 : 5 }
}

extension View {
    /// Shows `toast` at the bottom of the screen for 5 seconds. Setting a
    /// new one replaces it; Undo runs its action and closes it.
    func undoToast(_ toast: Binding<UndoToast?>) -> some View {
        modifier(UndoToastHost(toast: toast))
    }
}

private struct UndoToastHost: ViewModifier {
    @Binding var toast: UndoToast?
    @State private var undoCount = 0
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let toast {
                        bar(toast)
                            .id(toast.id)
                            .motionTransition(.undo, edge: .bottom)
                    }
                }
                .motion(.undo, value: toast?.id)
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.s)
            }
            .task(id: toast?.id) {
                guard let shown = toast else { return }
                AccessibilityNotification.Announcement(shown.message).post()
                try? await Task.sleep(nanoseconds: UInt64(UndoToast.duration * 1_000_000_000))
                guard !Task.isCancelled, toast?.id == shown.id else { return }
                withMotion(.undo) { toast = nil }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: undoCount)
    }

    private func bar(_ t: UndoToast) -> some View {
        let p = Palette(scheme: scheme)
        return HStack(spacing: Space.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.scaled(size: 17, weight: .semibold))
                .foregroundStyle(Accent.mint.ink(scheme))
                .accessibilityHidden(true)
            Text(t.message)
                .font(.bodyEmphasis)
                .foregroundStyle(p.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let undo = t.undo {
                Button {
                    undo()
                    undoCount += 1
                    withMotion(.undo) { toast = nil }
                } label: {
                    Text("Undo")
                        .font(.bodyEmphasis)
                        .foregroundStyle(Accent.indigo.ink(scheme))
                        .padding(.horizontal, Space.m)
                        .frame(minWidth: Sizes.minTap, minHeight: Sizes.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Undo: \(t.message)")
            }
        }
        .padding(.leading, Space.l)
        .padding(.trailing, t.undo == nil ? Space.l : Space.xs)
        .padding(.vertical, Space.xs)
        .frame(minHeight: Sizes.tallRow)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous).strokeBorder(p.cardBorder))
        .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}

/// "History ›": a small link from a logging section to its full screen,
/// where past entries are edited.
struct HistoryLink<Destination: View>: View {
    var title = "History"
    @ViewBuilder var destination: Destination
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationLink { destination } label: {
            HStack(spacing: Space.xs) {
                Text(title)
                Image(systemName: "chevron.right").font(.scaled(size: 11, weight: .bold)).accessibilityHidden(true)
            }
            .font(.scaled(size: 13, weight: .semibold))
            .foregroundStyle(Accent.indigo.ink(scheme))
            .keepsOnOneLine()
            .padding(.leading, Space.m)
            .textLinkHitArea()
        }
        .buttonStyle(.plain)
    }
}

/// A section label on the Log tab: the feature's icon in its colour, the
/// label in secondary (accent only on the icon), and an optional link on the
/// right.
struct LogSectionHeader<Trailing: View>: View {
    var title: String
    var systemImage: String
    var accent: Accent
    @ViewBuilder var trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .accessibilityHidden(true)
            CapsLabel(title)
            Spacer(minLength: Space.s)
            trailing
        }
        .padding(.top, Space.l)
    }
}

extension LogSectionHeader where Trailing == EmptyView {
    init(title: String, systemImage: String, accent: Accent) {
        self.init(title: title, systemImage: systemImage, accent: accent) { EmptyView() }
    }
}

/// A clock time with the am/pm at half the numeral size, semibold, in
/// secondary: "8:25" big, "am" small (Hale F9).
struct ClockText: View {
    var minutes: Minutes
    var role: TypeRole = .numberM
    /// A start time for a range: "8:00–8:25am".
    var from: Minutes? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let numerals = from.map { "\(Clock.format($0, suffix: Self.sameHalf($0, minutes) ? false : true))\u{2013}" } ?? ""
        let ampm = String(Clock.format(minutes).suffix(2))
        (Text(numerals + Clock.format(minutes, suffix: false)).font(role.font)
         + Text(ampm).font(.system(size: role.scaledSize * 0.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette(scheme: scheme).secondary))
            .accessibilityLabel(spoken)
    }

    /// "8:00 to 8:25am" for VoiceOver.
    private var spoken: String {
        guard let from else { return Clock.format(minutes) }
        return "\(Clock.format(from)) to \(Clock.format(minutes))"
    }

    /// Both am or both pm: the first time drops its suffix ("8:00–8:25am").
    static func sameHalf(_ a: Minutes, _ b: Minutes) -> Bool {
        Clock.format(a).suffix(2) == Clock.format(b).suffix(2)
    }
}
