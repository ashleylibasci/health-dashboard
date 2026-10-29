import SwiftUI
import WatchConnectivity
import WatchKit
import HealthCore

/// Today's pill on the Watch (H-F1): Taken from the Recovery page's row or
/// with one tap on the pill complication. The phone keeps the log; the
/// Watch shows the tick straight away and offers Undo for a few seconds.
@MainActor
final class WatchPillLog: ObservableObject {
    static let shared = WatchPillLog()

    /// Taken here a moment ago: the row offers Undo until this clears.
    @Published private(set) var undoable: Date?
    private var undoTask: Task<Void, Never>?

    /// Marks today's pill taken, unless it isn't a pill day or it's taken.
    func markTaken(_ sync: WatchSync, now: Date = .now) {
        guard let pill = sync.widget?.pill(at: now), pill.isPillDay, pill.taken == nil else { return }
        guard sync.send(.pillTaken(at: now)) else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        WKInterfaceDevice.current().play(.success)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            sync.setPillTaken(now)
            undoable = now
        }
        AccessibilityNotification.Announcement("Pill \(pill.packDay) taken. Tap Undo to undo.").post()
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.undoable = nil }
        }
    }

    /// The pill complication's tap: on a cold launch the connection to the
    /// phone takes a moment to come up, so wait for it (up to 3 seconds).
    func markTakenFromComplication(_ sync: WatchSync) async {
        for _ in 0..<15 where WCSession.default.activationState != .activated {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        markTaken(sync)
    }

    func undo(_ sync: WatchSync) {
        guard let at = undoable else { return }
        undoTask?.cancel()
        guard sync.send(.undoPill(at: at)) else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        WKInterfaceDevice.current().play(.directionDown)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            sync.setPillTaken(nil)
            undoable = nil
        }
        AccessibilityNotification.Announcement("Pill not taken").post()
    }
}

/// "Pill 18 of 28" with a Taken button; "Taken 9:02pm" with a tick once
/// it's taken (here, on the phone or in Apple Health); on break days the
/// break and when the new pack starts.
struct WatchPillRow: View {
    let pill: WidgetSnapshot.PillState
    @EnvironmentObject private var sync: WatchSync
    @ObservedObject private var log = WatchPillLog.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: pill.taken != nil ? "checkmark.circle.fill" : "pills.fill")
                .font(.headline)
                .foregroundStyle(pill.taken != nil ? Accent.mint.ink(.dark) : Accent.pink.ink(.dark))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(note)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            if log.undoable != nil, pill.taken != nil {
                Button("Undo") { log.undo(sync) }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .accessibilityLabel("Undo Taken")
            } else if pill.isPillDay, pill.taken == nil {
                Button {
                    log.markTaken(sync)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(hex: 0x2A0A1A))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Accent.pink.fill(.dark)))
                }
                .buttonStyle(WatchPressStyle())
                .accessibilityLabel("Mark pill \(pill.packDay) taken")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WatchStyle.surface))
    }

    private var title: String {
        if !pill.isPillDay { return pill.breakName }
        return pill.isNewPack ? "New pack \u{00B7} pill 1" : "Pill \(pill.packDay) of \(pill.packLength)"
    }

    private var note: String {
        if let taken = pill.taken { return "Taken \(WatchStyle.time(taken))" }
        if !pill.isPillDay {
            return pill.newPackDay.map { "New pack \($0.formatted(.dateTime.weekday(.abbreviated)))" } ?? "No pill today"
        }
        return "Take at \(Clock.format(pill.time))"
    }
}
