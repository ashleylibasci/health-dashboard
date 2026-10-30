import SwiftUI
import WatchConnectivity

/// The day-3 hello card (D-T7): under Today's greeting from her third
/// calendar day with the app until she closes it, three things that are easy to miss because
/// they live in Settings or outside the app. "Got it" or × closes it for
/// good.
struct HelloCard: View {
    /// The calendar day the app first opened (installs from before this
    /// card count from their first open after the update).
    @AppStorage("firstLaunchDay") private var firstLaunchDay: Double = 0
    @AppStorage("helloCardDone") private var done = false
    /// Closed in this run (`-demoHelloCard` ignores `done`).
    @State private var closed = false
    @State private var sheet: Sheet?
    @Environment(\.colorScheme) private var scheme

    private enum Sheet: String, Identifiable {
        case widget, watch
        var id: String { rawValue }
    }

    /// Called at launch: remembers the first day the app opened.
    static func recordFirstLaunch() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "firstLaunchDay") == nil else { return }
        defaults.set(Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate, forKey: "firstLaunchDay")
    }

    /// 1 on the day of the first launch, 3 two calendar days later.
    private var dayNumber: Int? {
        guard firstLaunchDay > 0 else { return nil }
        let cal = Calendar.current
        let first = Date(timeIntervalSinceReferenceDate: firstLaunchDay)
        return (cal.dateComponents([.day], from: cal.startOfDay(for: first), to: cal.startOfDay(for: .now)).day ?? 0) + 1
    }

    private var shows: Bool {
        guard !closed else { return false }
        return DemoMode.helloCard || (!done && (dayNumber ?? 0) >= 3)
    }

    /// Only while there's a Watch without the app on it.
    private var showsWatchRow: Bool {
        if DemoMode.helloCard { return true }
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && !session.isWatchAppInstalled
    }

    var body: some View {
        if shows {
            card
                .bottomSheet(item: $sheet, title: { $0 == .widget ? "Add a widget" : "Open it on your Watch" }) { which in
                    ForEach(WidgetsWatchSettingsView.howTos.filter {
                        which == .widget ? !$0.title.hasPrefix("Watch") : $0.title.hasPrefix("Watch")
                    }) { howTo in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Label(howTo.title, systemImage: howTo.systemImage).font(.bodyEmphasis)
                            Text(howTo.steps).font(.bodyText).secondaryText()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .motionTransition(.reveal, edge: .top)
        }
    }

    private var card: some View {
        let p = Palette(scheme: scheme)
        return RowCard(accent: .indigo) {
            HStack(spacing: Space.s) {
                CapsLabel("A few things you might miss", color: Accent.indigo.ink(scheme))
                Spacer(minLength: Space.s)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.scaled(size: 13, weight: .bold))
                        .foregroundStyle(p.secondary)
                        .frame(width: Sizes.minTap, height: Sizes.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .padding(.trailing, -Space.s)
            }
            .padding(.leading, Space.l)
            .padding(.trailing, Space.s)
            .padding(.top, Space.xs)
            MetricRow(title: "Add a widget", note: "Recovery and bedtime at a glance",
                      systemImage: "apps.iphone", accent: .indigo, action: { sheet = .widget })
            if showsWatchRow {
                RowDivider()
                MetricRow(title: "Open it on your Watch", note: "Fills in the Watch pages and complications",
                          systemImage: "applewatch", accent: .indigo, action: { sheet = .watch })
            }
            RowDivider()
            MetricRow(title: "Set your conditions", note: "So tips fit you, like PCOS or migraines",
                      systemImage: "heart.text.square.fill", accent: .pink) { ConditionsView() }
            Button(action: close) {
                Text("Got it")
                    .font(.bodyEmphasis)
                    .foregroundStyle(scheme == .dark ? Color(hex: 0x0D0E1C) : .white)
                    .padding(.horizontal, Space.l)
                    .frame(minHeight: Sizes.minTap)
                    .background(scheme == .dark ? Accent.indigo.fill(.dark) : Accent.indigo.ink(.light), in: Capsule())
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, Space.l)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
    }

    private func close() {
        withMotion(.reveal) { closed = true }
        done = true
    }
}
