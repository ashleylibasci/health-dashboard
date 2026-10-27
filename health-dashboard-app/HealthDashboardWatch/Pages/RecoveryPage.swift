import SwiftUI
import HealthCore

/// Today's recovery score as a ring, with the phone's one-line verdict.
struct RecoveryPage: View {
    @EnvironmentObject private var sync: WatchSync

    private var snapshot: WatchSnapshot { sync.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(title: "Recovery", accent: .indigo)
                if snapshot == .empty {
                    NotSyncedView()
                } else {
                    SnapshotStatusLine(snapshot: snapshot)
                    TimelineView(.everyMinute) { context in
                        content.staleStyle(snapshot.isStale(now: context.date))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// No score today (no heart readings and no recorded night).
    private var missing: Bool { snapshot.recoveryMissing == true }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RecoveryRing(value: missing ? nil : snapshot.recovery)
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 3) {
                    Text(missing ? "No reading yet" : (snapshot.recoveryLabel.isEmpty ? "Recovery" : snapshot.recoveryLabel))
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Text(missing ? "Wear your Watch to bed" : "out of 100")
                        .font(.system(size: 13))
                        .foregroundStyle(WatchStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(missing ? "Recovery: no reading yet. Wear your Watch to bed."
                                : "Recovery \(snapshot.recovery) out of 100. \(snapshot.recoveryLabel)")

            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Accent.mint.ink(.dark))
                    .accessibilityHidden(true)
                Text("Energy left \(snapshot.energyNow)%")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
    }
}

/// The big indigo ring with the score in the middle ("–" with no score).
private struct RecoveryRing: View {
    let value: Int?

    private var fraction: Double { min(max(Double(value ?? 0) / 100, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Accent.indigo.fill(.dark).opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(LinearGradient(colors: [Color(hex: 0x9AA6FF), Accent.indigo.fill(.dark)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(value.map { "\($0)" } ?? "\u{2013}")
                .font(.number(32))
                .minimumScaleFactor(0.6)
        }
        .padding(5)
    }
}
