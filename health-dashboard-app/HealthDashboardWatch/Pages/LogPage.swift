import SwiftUI
import WatchKit
import HealthCore

/// One-tap caffeine logging from the drinks saved on the iPhone.
struct LogPage: View {
    @EnvironmentObject private var sync: WatchSync

    /// Logged here, until a snapshot from the phone includes them.
    @State private var pending: [Logged] = []
    /// Undone here, until a snapshot from the phone no longer includes them.
    @State private var removed: [Logged] = []
    @State private var confirmation: String?
    /// The drink that can still be undone (for about 5 seconds).
    @State private var undoable: Logged?
    @State private var undoTask: Task<Void, Never>?

    private struct Logged: Equatable {
        var entryID: UUID
        var name: String
        var mg: Int
    }

    private var snapshot: WatchSnapshot { sync.snapshot }
    /// The phone's total, plus drinks sent from here it hasn't counted yet,
    /// minus drinks undone here it still counts.
    private var todayMg: Int {
        let counted = Set(snapshot.todayDrinkIDs ?? [])
        let added = pending.filter { !counted.contains($0.entryID) }.map(\.mg).reduce(0, +)
        let taken = removed.filter { counted.contains($0.entryID) }.map(\.mg).reduce(0, +)
        return max(0, snapshot.caffeineTodayMg + added - taken)
    }

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(title: "Log", accent: .yellow) {
                    if let cutoff = snapshot.caffeineCutoff {
                        Text("cutoff \(WatchStyle.time(cutoff))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xD9CDA6))
                    }
                }
                if snapshot == .empty {
                    NotSyncedView()
                } else {
                    SnapshotStatusLine(snapshot: snapshot)
                    summary
                    undoButton
                    drinks
                }
            }
            .padding(.horizontal, 4)
        }
        .onChange(of: snapshot) { old, new in
            if let ids = new.todayDrinkIDs {
                // Keep only what the phone hasn't caught up with yet.
                let counted = Set(ids)
                pending.removeAll { counted.contains($0.entryID) }
                removed.removeAll { !counted.contains($0.entryID) }
            } else if new.syncedAt != old.syncedAt {
                // Older phone builds: a new snapshot counts everything sent.
                pending = []
                removed = []
            }
        }
    }

    // MARK: Today vs cutoff

    private var summary: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(todayMg)")
                        .font(.number(28))
                    Text("mg today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xE6DAB0))
                }
                if let error = sync.deliveryError {
                    Text(error)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Accent.coral.ink(.dark))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(confirmation ?? cutoffText(now: context.date))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(confirmation == nil && isPastCutoff(context.date) ? Accent.coral.ink(.dark) : WatchStyle.secondaryText)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .staleStyle(snapshot.isStale(now: context.date))
        }
    }

    @ViewBuilder
    private var undoButton: some View {
        if let undoable {
            Button {
                undo(undoable)
            } label: {
                Label("Undo \(undoable.name)", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .tint(Accent.yellow.fill(.dark))
            .accessibilityLabel("Undo \(undoable.name)")
        }
    }

    private func isPastCutoff(_ now: Date) -> Bool {
        guard let cutoff = snapshot.caffeineCutoff else { return false }
        return now >= cutoff
    }

    private func cutoffText(now: Date) -> String {
        if snapshot.caffeineCutoffBeforeWake == true {
            return "Caffeine lasts longer for you. Keep it to one small drink, early."
        }
        guard let cutoff = snapshot.caffeineCutoff else { return "No cutoff set" }
        if now >= cutoff { return "Past your cutoff. It may cost you sleep." }
        let minutes = Int(cutoff.timeIntervalSince(now) / 60)
        return "Cutoff in \(Clock.duration(minutes))"
    }

    // MARK: Drinks

    @ViewBuilder
    private var drinks: some View {
        if snapshot.quickDrinks.isEmpty {
            Text("Save drinks on your iPhone to log them here.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WatchStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(snapshot.quickDrinks) { drink in
                    Button {
                        log(drink)
                    } label: {
                        DrinkTile(drink: drink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log \(drink.name), \(drink.caffeineMg) milligrams of caffeine")
                }
            }
        }
    }

    /// Sends the drink to the phone with the tap time and its own id. The
    /// phone adds it to the log and saves it to Apple Health (once), so the
    /// Watch doesn't write to Health itself.
    @MainActor
    private func log(_ drink: WatchSnapshot.QuickDrink) {
        let entry = Logged(entryID: UUID(), name: drink.name, mg: drink.caffeineMg)
        guard sync.send(.loggedDrinkEntry(entryID: entry.entryID, drinkID: drink.id, name: drink.name,
                                          mg: drink.caffeineMg, at: Date())) else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        WKInterfaceDevice.current().play(.success)
        pending.append(entry)
        confirmation = "Logged \(drink.name)"
        undoable = entry
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            undoable = nil
            confirmation = nil
        }
    }

    @MainActor
    private func undo(_ entry: Logged) {
        undoTask?.cancel()
        undoable = nil
        guard sync.send(.undoDrink(entryID: entry.entryID)) else { return }
        WKInterfaceDevice.current().play(.click)
        if pending.contains(entry) {
            pending.removeAll { $0 == entry }
            // The phone may have counted it already; subtract until it hasn't.
            if snapshot.todayDrinkIDs?.contains(entry.entryID) == true { removed.append(entry) }
        } else {
            removed.append(entry)
        }
        confirmation = "Removed \(entry.name)"
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            confirmation = nil
        }
    }
}

private struct DrinkTile: View {
    let drink: WatchSnapshot.QuickDrink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Circle()
                    .fill(Accent.yellow.fill(.dark).opacity(0.22))
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Accent.yellow.ink(.dark))
            }
            .frame(width: 32, height: 32)
            Spacer(minLength: 0)
            Text(drink.name)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("+\(drink.caffeineMg) mg")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0xE6DAB0))
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Accent.yellow.fill(.dark).opacity(0.2)))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
