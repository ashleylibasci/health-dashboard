import SwiftUI
import WatchKit
import HealthCore

/// One-tap caffeine and water logging: today's total first, then the drinks
/// saved on the iPhone (and a bottle of water), then what the cutoff means.
/// A logged tile turns into its own Undo for a few seconds, so nothing on the
/// page moves.
struct LogPage: View {
    @EnvironmentObject private var sync: WatchSync

    /// Logged here, until a snapshot from the phone includes them.
    @State private var pending: [Logged] = []
    /// Undone here, until a snapshot from the phone no longer includes them.
    @State private var removed: [Logged] = []
    /// The entry that can still be undone (for about 5 seconds), shown on its
    /// own tile.
    @State private var undoable: Logged?
    @State private var undoTask: Task<Void, Never>?

    private struct Logged: Equatable {
        enum Kind: Equatable {
            case drink(mg: Int)
            case water(ml: Double)
        }
        var entryID: UUID
        /// The tile it was logged from: a saved drink's id, or `waterTile`.
        var tile: String
        var name: String
        var kind: Kind

        var mg: Int { if case let .drink(mg) = kind { return mg }; return 0 }
        var ml: Double { if case let .water(ml) = kind { return ml }; return 0 }
        var isWater: Bool { if case .water = kind { return true }; return false }
    }

    private static let waterTile = "water"
    private static let mlPerOz = 29.5735

    private var snapshot: WatchSnapshot { sync.snapshot }

    /// The phone's total, plus drinks sent from here it hasn't counted yet,
    /// minus drinks undone here it still counts. Only drinks logged here
    /// once a new day has started.
    private func todayMg(_ now: Date) -> Int {
        let fresh = !snapshot.isFromEarlierDay(now: now)
        let counted = fresh ? Set(snapshot.todayDrinkIDs ?? []) : []
        let drinks = pending.filter { !$0.isWater }
        let added = drinks.filter { !counted.contains($0.entryID) }.map(\.mg).reduce(0, +)
        let taken = removed.filter { !$0.isWater && counted.contains($0.entryID) }.map(\.mg).reduce(0, +)
        return max(0, (fresh ? snapshot.caffeineTodayMg : 0) + added - taken)
    }

    /// The same for water, in ml; nil from phone builds that can't log water
    /// from the Watch.
    private func todayWaterML(_ now: Date) -> Double? {
        guard let base = snapshot.waterTodayML else { return nil }
        let fresh = !snapshot.isFromEarlierDay(now: now)
        let counted = fresh ? Set(snapshot.todayWaterIDs ?? []) : []
        let added = pending.filter { $0.isWater && !counted.contains($0.entryID) }.map(\.ml).reduce(0, +)
        let taken = removed.filter { $0.isWater && counted.contains($0.entryID) }.map(\.ml).reduce(0, +)
        return max(0, (fresh ? base : 0) + added - taken)
    }

    /// Today's cutoff; not yesterday's.
    private func cutoff(_ now: Date) -> Date? {
        snapshot.isFromEarlierDay(now: now) ? nil : snapshot.caffeineCutoff
    }

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        WatchPage(title: "Log", accent: .yellow) {
            TimelineView(.everyMinute) { context in
                let now = context.date
                VStack(alignment: .leading, spacing: 10) {
                    SnapshotStatusLine(snapshot: snapshot, now: now)
                    if let error = sync.deliveryError {
                        Text(error)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Accent.coral.ink(.dark))
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                    totals(now: now)
                    tiles
                    explainer(now: now)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: sync.deliveryError)
            }
        }
        .onChange(of: snapshot) { old, new in
            if let ids = new.todayDrinkIDs {
                // Keep only what the phone hasn't caught up with yet.
                let counted = Set(ids).union(new.todayWaterIDs ?? [])
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

    /// "130 mg · past cutoff", with today's water under it.
    private func totals(now: Date) -> some View {
        let mg = todayMg(now)
        let tag = statusTag(now)
        let number = HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(mg)")
                .font(WatchStyle.number(.title2))
                .contentTransition(.numericText(value: Double(mg)))
            Text("mg today")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.caffeineText)
        }
        let tagText = tag.map { t in
            Text(t.text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(t.warning ? Accent.coral.ink(.dark) : WatchStyle.caffeineText)
        }
        return VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    number
                    if let tagText {
                        Text("\u{00B7}").font(.footnote.weight(.semibold)).foregroundStyle(WatchStyle.caffeineText)
                        tagText.lineLimit(1)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    number
                    tagText?.fixedSize(horizontal: false, vertical: true)
                }
            }
            if let ml = todayWaterML(now) {
                let goal = snapshot.waterGoalML ?? 0
                Text(goal > 0 ? "\(oz(ml)) of \(oz(goal)) oz water" : "\(oz(ml)) oz water")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Accent.blue.ink(.dark))
                    .contentTransition(.numericText(value: ml))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: mg)
        .accessibilityElement(children: .combine)
        .staleStyle(snapshot.isStale(now: now) && !snapshot.isFromEarlierDay(now: now))
    }

    private func oz(_ ml: Double) -> String { "\(Int((ml / Self.mlPerOz).rounded()))" }

    /// The short state after the total: the cutoff time, or "past cutoff"
    /// in coral (the only coral on the page: something to act on).
    private func statusTag(_ now: Date) -> (text: String, warning: Bool)? {
        if showsWarning(now) {
            return isPastCutoff(now) ? ("past cutoff", true) : ("lingers at bedtime", true)
        }
        if snapshot.caffeineCutoffBeforeWake == true, !snapshot.isFromEarlierDay(now: now) {
            return ("cutoff before you\u{2019}re up", false)
        }
        guard let cutoff = cutoff(now) else { return nil }
        if now >= cutoff { return ("past cutoff", true) }
        return ("cutoff \(WatchStyle.time(cutoff))", false)
    }

    private func isPastCutoff(_ now: Date) -> Bool {
        guard let cutoff = cutoff(now) else { return false }
        return now >= cutoff
    }

    /// Drinks logged here since the last phone update, after the cutoff.
    private func loggedHereAfterCutoff(_ now: Date) -> Bool {
        let counted = Set(snapshot.todayDrinkIDs ?? [])
        return isPastCutoff(now) && pending.contains { !$0.isWater && !counted.contains($0.entryID) && $0.mg > 0 }
    }

    /// The only warning: today's caffeine would still be around at bedtime
    /// (from the phone's numbers, or a drink just logged here past the
    /// cutoff). Never with 0 mg.
    private func showsWarning(_ now: Date) -> Bool {
        guard todayMg(now) > 0 else { return false }
        let phoneSays = snapshot.caffeineTooMuchAtBedtime == true && !snapshot.isFromEarlierDay(now: now)
        return phoneSays || loggedHereAfterCutoff(now)
    }

    /// What the cutoff means, under the tiles.
    private func explainer(now: Date) -> some View {
        let warning = showsWarning(now)
        return Text(cutoffText(now: now))
            .font(.footnote)
            .foregroundStyle(warning ? Accent.coral.ink(.dark) : WatchStyle.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func cutoffText(now: Date) -> String {
        if showsWarning(now) {
            return "Some of today\u{2019}s caffeine will still be in you at bedtime. It may make sleep lighter."
        }
        if snapshot.isFromEarlierDay(now: now) {
            return "Open Health Dashboard on your iPhone for today\u{2019}s cutoff."
        }
        if snapshot.caffeineCutoffBeforeWake == true {
            return "No time works for a full coffee today: caffeine lasts longer for you. One small drink, early."
        }
        guard let cutoff = cutoff(now) else { return "No cutoff set." }
        if now >= cutoff {
            return todayMg(now) == 0
                ? "No caffeine today. Your cutoff was \(WatchStyle.time(cutoff)), so skip it from here."
                : "More caffeine now would still be in you at bedtime."
        }
        let minutes = Int(cutoff.timeIntervalSince(now) / 60)
        return "Last caffeine by \(WatchStyle.time(cutoff)), in \(Clock.duration(minutes)), so it\u{2019}s gone by bedtime."
    }

    // MARK: Tiles

    @ViewBuilder
    private var tiles: some View {
        let bottle = snapshot.bottleML.flatMap { $0 > 0 ? $0 : nil }
        if snapshot.quickDrinks.isEmpty && bottle == nil {
            Text("Save drinks on your iPhone to log them here.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(WatchStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(snapshot.quickDrinks) { drink in
                    let tile = drink.id.uuidString
                    tileButton(tile: tile, name: drink.name, accent: .yellow,
                               symbol: DrinkTile.symbol(for: drink.name), amount: "+\(drink.caffeineMg) mg",
                               label: "Log \(drink.name), \(drink.caffeineMg) milligrams of caffeine") {
                        log(drink)
                    }
                }
                if let bottle {
                    tileButton(tile: Self.waterTile, name: "Bottle", accent: .blue, symbol: "waterbottle.fill",
                               amount: "+\(oz(bottle)) oz", label: "Log a bottle of water, \(oz(bottle)) ounces") {
                        logWater(ml: bottle)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: waterGoalReached) { old, new in !old && new }
        }
    }

    /// True once today's water reaches her goal (for one success tap).
    private var waterGoalReached: Bool {
        guard let goal = snapshot.waterGoalML, goal > 0, let ml = todayWaterML(.now) else { return false }
        return ml >= goal
    }

    /// A drink or water tile; while its entry can be undone, the same tile
    /// is the Undo button.
    private func tileButton(tile: String, name: String, accent: Accent, symbol: String, amount: String,
                            label: String, log: @escaping () -> Void) -> some View {
        let undo = undoable?.tile == tile ? undoable : nil
        return Button {
            if let undo { self.undo(undo) } else { log() }
        } label: {
            DrinkTile(name: name, symbol: symbol, amount: amount, accent: accent, undoing: undo != nil)
        }
        .buttonStyle(WatchPressStyle())
        .accessibilityLabel(undo.map { "Undo \($0.name)" } ?? label)
    }

    /// Sends the drink to the phone with the tap time and its own id. The
    /// phone adds it to the log and saves it to Apple Health (once), so the
    /// Watch doesn't write to Health itself.
    @MainActor
    private func log(_ drink: WatchSnapshot.QuickDrink) {
        let entry = Logged(entryID: UUID(), tile: drink.id.uuidString, name: drink.name, kind: .drink(mg: drink.caffeineMg))
        guard sync.send(.loggedDrinkEntry(entryID: entry.entryID, drinkID: drink.id, name: drink.name,
                                          mg: drink.caffeineMg, at: Date())) else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        logged(entry)
    }

    @MainActor
    private func logWater(ml: Double) {
        let entry = Logged(entryID: UUID(), tile: Self.waterTile, name: "Water", kind: .water(ml: ml))
        guard sync.send(.loggedWater(entryID: entry.entryID, ml: ml, at: Date())) else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        logged(entry)
    }

    @MainActor
    private func logged(_ entry: Logged) {
        WKInterfaceDevice.current().play(.directionUp)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            pending.append(entry)
            undoable = entry
        }
        AccessibilityNotification.Announcement("Logged \(entry.name). Tap again to undo.").post()
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { undoable = nil }
        }
    }

    @MainActor
    private func undo(_ entry: Logged) {
        undoTask?.cancel()
        let message: WatchMessage = entry.isWater ? .undoWater(entryID: entry.entryID) : .undoDrink(entryID: entry.entryID)
        guard sync.send(message) else {
            WKInterfaceDevice.current().play(.failure)
            withAnimation { undoable = nil }
            return
        }
        WKInterfaceDevice.current().play(.directionDown)
        let counted = Set((snapshot.todayDrinkIDs ?? []) + (snapshot.todayWaterIDs ?? []))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            undoable = nil
            if pending.contains(entry) {
                pending.removeAll { $0 == entry }
                // The phone may have counted it already; subtract until it hasn't.
                if counted.contains(entry.entryID) { removed.append(entry) }
            } else {
                removed.append(entry)
            }
        }
        AccessibilityNotification.Announcement("Removed \(entry.name)").post()
    }
}

/// A drink tile: icon and amount on top, the name under them. While it can
/// be undone it shows a check and "Undo" instead, in the same space.
private struct DrinkTile: View {
    let name: String
    let symbol: String
    let amount: String
    let accent: Accent
    var undoing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(accent.fill(.dark).opacity(undoing ? 0.9 : 0.22))
                    Image(systemName: undoing ? "checkmark" : symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(undoing ? Color.black : accent.ink(.dark))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 24, height: 24)
                Spacer(minLength: 0)
                Text(undoing ? "Logged" : amount)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(undoing ? accent.ink(.dark) : WatchStyle.caffeineText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
            }
            Group {
                if undoing {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Text(name)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(accent.fill(.dark).opacity(undoing ? 0.32 : 0.2)))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// A symbol that fits the drink's name.
    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if has("matcha", "chai", " tea", "tea ") || n == "tea" { return "leaf.fill" }
        if has("energy", "red bull", "monster", "celsius", "bang", "prime") { return "bolt.fill" }
        if has("soda", "cola", "coke", "pepsi", "dr pepper", "mountain dew") { return "takeoutbag.and.cup.and.straw.fill" }
        if has("cold brew", "iced", "frapp") { return "takeoutbag.and.cup.and.straw.fill" }
        if has("latte", "cappuccino", "mocha", "flat white", "mug") { return "mug.fill" }
        return "cup.and.saucer.fill"
    }
}
