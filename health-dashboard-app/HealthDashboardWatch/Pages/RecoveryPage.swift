import SwiftUI
import HealthCore

/// Today's recovery score as a ring, with the phone's one-line verdict, a
/// way through to Energy, and where she is in her cycle (today's pill with
/// its Taken button, on the combined pill).
struct RecoveryPage: View {
    /// Moves to the Energy page.
    var openEnergy: () -> Void = {}
    @EnvironmentObject private var sync: WatchSync

    private var snapshot: WatchSnapshot { sync.snapshot }

    var body: some View {
        WatchPage(title: "Recovery", accent: .indigo) {
            TimelineView(.everyMinute) { context in
                let now = context.date
                VStack(alignment: .leading, spacing: 10) {
                    SnapshotStatusLine(snapshot: snapshot, now: now)
                    if snapshot.isFromEarlierDay(now: now) {
                        // Yesterday's score isn't today's.
                        NotTodayView(what: "recovery score")
                    } else {
                        score.staleStyle(snapshot.isStale(now: now))
                        energyButton.staleStyle(snapshot.isStale(now: now))
                        morningLight(now: now).staleStyle(snapshot.isStale(now: now))
                    }
                    DownshiftOffer(snapshot: snapshot, now: now)
                    cycleRow(now: now)
                }
            }
        }
        .onChange(of: sync.widget) { WatchPillLog.shared.reconcile(sync) }
    }

    /// No score today (no heart readings and no recorded night).
    private var missing: Bool { snapshot.recoveryMissing == true }

    private var score: some View {
        HStack(spacing: 10) {
            RecoveryRing(value: missing ? nil : snapshot.recovery)
            VStack(alignment: .leading, spacing: 2) {
                Text(missing ? "No reading yet" : (snapshot.recoveryLabel.isEmpty ? "Recovery" : snapshot.recoveryLabel))
                    .font(.headline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                if missing {
                    Text("Wear your Watch to bed")
                        .font(.footnote)
                        .foregroundStyle(WatchStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(missing ? "Recovery: no reading yet. Wear your Watch to bed."
                            : "Recovery \(snapshot.recovery) out of 100. \(snapshot.recoveryLabel)")
    }

    /// "Energy left 17%", which opens the Energy page.
    private var energyButton: some View {
        Button(action: openEnergy) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Accent.mint.ink(.dark))
                    .accessibilityHidden(true)
                Text("Energy left")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text("\(snapshot.energyNow)%")
                    .font(WatchStyle.number(.headline))
                    .contentTransition(.numericText(value: Double(snapshot.energyNow)))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WatchStyle.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Capsule().fill(Accent.mint.fill(.dark).opacity(0.16)))
            .contentShape(Capsule())
        }
        .buttonStyle(WatchPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energy left \(snapshot.energyNow) percent")
        .accessibilityHint("Opens the Energy page")
        .accessibilityAddTraits(.isButton)
    }

    /// Morning daylight against her 20 minutes before 11am (H-F4), the
    /// same as the phone's Sleep tab, until 11am.
    @ViewBuilder
    private func morningLight(now: Date) -> some View {
        if let got = snapshot.morningLightMinutes, let goal = snapshot.morningLightGoal, goal > 0, isMorning(now) {
            let done = got >= goal
            HStack(spacing: 10) {
                DaylightRing(fraction: Double(got) / Double(goal), done: done)
                VStack(alignment: .leading, spacing: 0) {
                    Text(done ? "Morning light done" : "\(got) of \(goal) min")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("outside before 11am")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Morning light: \(got) of \(goal) minutes outside before 11am")
        }
    }

    /// Before 11am. Debug builds: `-demoMorning` shows the ring at any
    /// hour, for simulator screenshots.
    private func isMorning(_ now: Date) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoMorning") { return true }
        #endif
        return Calendar.current.component(.hour, from: now) < 11
    }

    /// Today's pill on the combined pill; otherwise "Day 12 · Follicular",
    /// from the phone's widget numbers (today's only). Nothing when she
    /// isn't tracking a cycle.
    @ViewBuilder
    private func cycleRow(now: Date) -> some View {
        if let pill = sync.widget?.pill(at: now) {
            WatchPillRow(pill: pill)
        } else if let line = sync.widget?.cycleLine(at: now) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.footnote)
                    .foregroundStyle(Accent.pink.ink(.dark))
                    .accessibilityHidden(true)
                Text(line)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cycle: \(line)")
        }
    }
}

/// A small yellow ring of morning daylight, with a sun (a tick once done).
private struct DaylightRing: View {
    let fraction: Double
    let done: Bool
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        ZStack {
            Circle().stroke(Accent.yellow.fill(.dark).opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(Accent.yellow.fill(.dark), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(luminanceReduced ? 0.6 : 1)
            Image(systemName: done ? "checkmark" : "sun.max.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Accent.yellow.ink(.dark))
        }
        .frame(width: 34, height: 34)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
    }
}

/// The indigo ring with the score in the middle and "of 100" under it ("–"
/// with no score).
private struct RecoveryRing: View {
    let value: Int?
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 84
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private let lineWidth: CGFloat = 9
    private var fraction: Double { min(max(Double(value ?? 0) / 100, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(Accent.indigo.fill(.dark).opacity(0.2), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [WatchStyle.recoveryRingStart, Accent.indigo.fill(.dark)],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(luminanceReduced ? 0.6 : 1)
            VStack(spacing: -1) {
                Text(value.map { "\($0)" } ?? "\u{2013}")
                    .font(WatchStyle.number(.title2))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(value ?? 0)))
                if value != nil {
                    Text("of 100")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WatchStyle.secondaryText)
                }
            }
            .padding(.horizontal, lineWidth + 4)
        }
        .frame(width: min(size, 104), height: min(size, 104))
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}
