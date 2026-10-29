import SwiftUI
import HealthCore

/// "Your packs": the pill-history rows on Cycle, each one line with its
/// page one tap down. Combined pill only; a row shows once it has
/// something to say.
struct PackHistoryRows: View {
    @EnvironmentObject var model: AppModel
    @State private var showsPattern = false

    var body: some View {
        let bleeds = model.packBleeds
        let mood = model.moodByPackDay(.mood)
        let showsMood = !(mood?.points.isEmpty ?? true)
        let pattern = model.breakWeekPatternLine
        if !bleeds.isEmpty || showsMood || pattern != nil {
            RowCard {
                if let pattern {
                    MetricRow(title: "Your \(model.breaksPhrase)", note: pattern,
                              systemImage: "calendar.badge.exclamationmark", accent: .pink) { showsPattern = true }
                    if showsMood || !bleeds.isEmpty { RowDivider() }
                }
                if let mood, showsMood {
                    MetricRow(title: "Mood by pack day", note: moodNote(mood),
                              systemImage: "face.smiling", accent: .orange) {
                        MoodByPackDayView()
                    }
                }
                if !bleeds.isEmpty {
                    if showsMood { RowDivider() }
                    MetricRow(title: "Bleeds by pack", note: bleedNote(bleeds),
                              systemImage: "drop.fill", accent: .pink) {
                        BleedsByPackView()
                    }
                }
            }
            .bottomSheet(isPresented: $showsPattern, title: "Your \(model.breaksPhrase)") {
                Text(pattern ?? "")
                    .font(.cardTitle).fixedSize(horizontal: false, vertical: true)
                Text("From your last \(BreakWeekPattern.packsNeeded) packs: what you logged on break days compared with active-pill days. Headaches, pelvic pain and mood changes in the break are common on the pill, from the drop in hormones.")
                    .font(.bodyText).fixedSize(horizontal: false, vertical: true)
                Text("A shorter break (24 + 4 packs) or skipping the break helps many people, so it\u{2019}s something concrete to raise at your pill visit.")
                    .font(.bodyText).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Lower in your break week" once there are two packs, else how far along.
    private func moodNote(_ mood: MoodByPackDay) -> String {
        guard mood.isReady, let pack = model.pillPack else {
            return "Fills in after \(MoodByPackDay.packsNeeded) packs \u{00B7} \(mood.packsCovered) so far"
        }
        let split = mood.split(activeDays: pack.activeDays)
        guard pack.hasBreak, let a = split.active, let b = split.breakDays else { return "Your mood across the pack" }
        if a - b >= MoodPattern.meaningfulShift { return "Lower in your \(model.packBreakName.lowercased())" }
        if b - a >= MoodPattern.meaningfulShift { return "Higher in your \(model.packBreakName.lowercased())" }
        return "About the same all pack"
    }

    /// "Last one: 4 days, heaviest medium".
    private func bleedNote(_ bleeds: [PackBleeds.Pack]) -> String {
        guard let last = bleeds.first(where: { $0.bleedDays > 0 }) else { return "No withdrawal bleeds logged" }
        return "Last one: \(last.bleedDays) day\(last.bleedDays == 1 ? "" : "s"), heaviest \(AppModel.flowWord(last.heaviest))"
    }
}

// MARK: - Bleeds by pack (H-A10)

/// Each pack's withdrawal bleed as a row of day dots, newest first, with
/// any bleeding on active pills under it.
struct BleedsByPackView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let bleeds = model.packBleeds
        Screen(title: "Bleeds by pack", accent: .pink) {
            SampleDataBanner()
            SummaryHeader(eyebrow: "Your last \(bleeds.count) pack\(bleeds.count == 1 ? "" : "s")",
                          value: averageDays(bleeds), line: trendLine(bleeds), accent: .pink)
            Card {
                ForEach(Array(bleeds.enumerated()), id: \.element.pack) { i, pack in
                    if i > 0 { Divider().overlay(Palette(scheme: scheme).cardBorder) }
                    packRow(pack)
                }
                legend
            }
            Text("Lighter, shorter bleeds are normal on the pill, and so is the odd pack with none. It\u{2019}s a record for you and for your pill visit.")
                .font(.secondary).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "4 days on average" (packs with a bleed only).
    private func averageDays(_ bleeds: [PackBleeds.Pack]) -> String {
        let days = bleeds.map(\.bleedDays).filter { $0 > 0 }
        guard !days.isEmpty else { return "None logged" }
        let avg = Double(days.reduce(0, +)) / Double(days.count)
        return "\(Int(avg.rounded())) days on average"
    }

    /// Lighter or shorter than the first of these packs, or about the same.
    private func trendLine(_ bleeds: [PackBleeds.Pack]) -> String {
        let withBleed = bleeds.filter { $0.bleedDays > 0 }
        guard let newest = withBleed.first, let oldest = withBleed.last, withBleed.count >= 3 else {
            return "Each pack\u{2019}s bleed, from what you logged."
        }
        if newest.bleedDays < oldest.bleedDays || (newest.heaviest ?? .spotting) < (oldest.heaviest ?? .spotting) {
            return "Getting lighter or shorter since \(model.packDateRange(oldest.pack).components(separatedBy: "\u{2013}").first ?? "then")."
        }
        return "About the same from pack to pack."
    }

    private func packRow(_ pack: PackBleeds.Pack) -> some View {
        let p = Palette(scheme: scheme)
        let days = pack.days.keys.sorted()
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.packDateRange(pack.pack)).font(.bodyEmphasis)
                Spacer(minLength: Space.s)
                Text(pack.bleedDays == 0 ? "No bleed logged"
                     : "\(pack.bleedDays) day\(pack.bleedDays == 1 ? "" : "s") \u{00B7} \(AppModel.flowWord(pack.heaviest))")
                    .font(.secondary).fontWeight(.semibold).foregroundStyle(p.secondary)
            }
            if !days.isEmpty {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { d in
                        Circle().fill(color(pack.days[d])).frame(width: dotSize(pack.days[d]), height: dotSize(pack.days[d]))
                            .frame(width: 18, height: 18)
                    }
                }
                .accessibilityHidden(true)
            }
            if pack.activeDays > 0 {
                Text("Spotting or bleeding on \(pack.activeDays) active-pill day\(pack.activeDays == 1 ? "" : "s")")
                    .font(.secondary).foregroundStyle(p.secondary)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }

    /// Bigger and stronger for heavier flow.
    private func dotSize(_ level: PackBleeds.Level?) -> CGFloat {
        switch level {
        case .heavy?: 18
        case .medium?: 14
        case .light?: 11
        default: 8
        }
    }

    private func color(_ level: PackBleeds.Level?) -> Color {
        let pink = Accent.pink.fill(scheme)
        switch level {
        case .heavy?: return pink
        case .medium?: return pink.opacity(0.8)
        case .light?: return pink.opacity(0.6)
        default: return pink.opacity(0.4)
        }
    }

    private var legend: some View {
        HStack(spacing: Space.m) {
            ForEach([PackBleeds.Level.spotting, .light, .medium, .heavy], id: \.self) { level in
                HStack(spacing: 4) {
                    Circle().fill(color(level)).frame(width: dotSize(level), height: dotSize(level))
                        .accessibilityHidden(true)
                    Text(AppModel.flowWord(level).capitalized).font(.small).secondaryText()
                }
            }
        }
        .padding(.top, Space.xs)
    }
}
