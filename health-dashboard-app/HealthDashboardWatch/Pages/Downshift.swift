import SwiftUI
import WatchKit

/// The one-minute downshift (F5): when her stress read "High" while she
/// was still, this hour or the last, the Recovery page offers a minute of
/// slow breathing. Offered, never pushed: no alert, no buzz, and nothing
/// says what her stress "means". Slow breathing modestly lowers felt
/// anxiety (Zaccaro 2018).
struct DownshiftOffer: View {
    let snapshot: WatchSnapshot
    let now: Date
    @State private var breathing = false

    /// The reading is from this hour or the last (90 minutes at most).
    static func isOffered(_ snapshot: WatchSnapshot, now: Date) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-breathe") { return true }
        #endif
        guard let high = snapshot.stressHighAt else { return false }
        return now.timeIntervalSince(high) < 2 * 3600 && now >= high
    }

    var body: some View {
        if Self.isOffered(snapshot, now: now) {
            Button { breathing = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wind")
                        .foregroundStyle(Accent.mint.ink(.dark))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("A minute to breathe?")
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your heart\u{2019}s been busy")
                            .font(.caption2)
                            .foregroundStyle(WatchStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Accent.mint.fill(.dark).opacity(0.16)))
                .contentShape(Rectangle())
            }
            .buttonStyle(WatchPressStyle())
            .accessibilityLabel("A minute to breathe? Your heart's been busy.")
            .accessibilityHint("Starts one minute of slow breathing")
            .fullScreenCover(isPresented: $breathing) { BreatheView() }
            .onAppear {
                // Debug builds: `-breathe open` starts the breather, for
                // simulator screenshots.
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-breathe"), i + 1 < args.count, args[i + 1] == "open" { breathing = true }
                #endif
            }
        }
    }
}

/// One minute of slow breathing at 6 breaths a minute: 5 seconds in, 5
/// out, six times, with a gentle tap at each turn. The cover's ✕ stops it
/// any time.
struct BreatheView: View {
    static let breaths = 6
    static let half: TimeInterval = 5

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var lastPhase = -1

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let total = Double(Self.breaths) * Self.half * 2
            let done = elapsed >= total
            let phase = Int(elapsed / Self.half)
            let inhaling = phase % 2 == 0
            // 0 → 1 breathing in, 1 → 0 breathing out, eased.
            let t = (elapsed - Double(phase) * Self.half) / Self.half
            let eased = (1 - cos(.pi * t)) / 2
            let fill = done ? 0 : (inhaling ? eased : 1 - eased)
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Accent.mint.fill(.dark).opacity(0.18))
                    Circle()
                        .fill(Accent.mint.fill(.dark).opacity(0.55))
                        .scaleEffect(reduceMotion ? 0.7 : 0.35 + 0.65 * fill)
                        .opacity(reduceMotion ? 0.4 + 0.6 * fill : 1)
                }
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
                Text(done ? "Done" : (inhaling ? "Breathe in" : "Breathe out"))
                    .font(.headline)
                    .contentTransition(.opacity)
                Text(done ? "Nice. Back to your day." : "\(max(Self.breaths - phase / 2, 1)) of \(Self.breaths) breaths left")
                    .font(.caption2)
                    .foregroundStyle(WatchStyle.secondaryText)
                if done {
                    Button("Close") { dismiss() }
                        .font(.footnote.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: done ? -2 : phase) { _, new in
                // A soft tap at each turn, and a finish tap.
                guard new != lastPhase else { return }
                lastPhase = new
                WKInterfaceDevice.current().play(new == -2 ? .success : (new % 2 == 0 ? .directionUp : .directionDown))
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            start = .now
            WKInterfaceDevice.current().play(.start)
        }
    }
}
