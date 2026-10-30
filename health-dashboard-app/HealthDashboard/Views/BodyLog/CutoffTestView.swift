import SwiftUI
import Charts
import HealthCore

/// The caffeine cutoff test: your average sleep grouped by when your last
/// caffeine was, so you can find your own cutoff instead of a general rule.
struct CutoffTestView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    @State private var selected: String?

    private var test: CaffeineCutoffTest { model.cutoffTest }

    var body: some View {
        // One title, the nav title; caffeine is yellow (Valtonen F8, Tanaka F4).
        Screen(title: "Find your caffeine limit", accent: .yellow) {
            SampleDataBanner()
            header
            resultCard
            RowCard {
                ExpandRow(title: "How to do the test", summary: "Three steps, about three weeks",
                          systemImage: "list.number", accent: .yellow) {
                    step(1, "Log every caffeinated drink at the time you had it. You can change times later on the Caffeine screen.")
                    step(2, "Mix it up a little: some days stop before noon, some days a bit later.")
                    step(3, "Wear your watch to bed. That's it.")
                    Text("A night counts when your watch tracked your sleep. Days you logged no caffeine count too, as \u{201C}No caffeine\u{201D}.")
                        .font(.secondary)
                }
            }
            Card(density: .compact) {
                HowWeGotThisLink(title: "Find your caffeine limit",
                                 method: "From the day you first logged caffeine, we take each night's last caffeinated drink (from 4am the day before until you fell asleep) and how long you slept (from your Apple Watch). Nights go into groups: no caffeine, last caffeine before 12pm, 12 to 3pm, and after 3pm (drinks after midnight count as late). Each bar is the average sleep in that group. We compare the earliest and latest caffeine groups once each has at least \(HabitEffect.minimumNights) nights, and a difference has to be big enough to stand out from ordinary night-to-night swings: about 45 minutes with 5 nights in each group, shrinking to about 20 minutes with 30 or more.")
            }
        }
    }

    // MARK: Summary

    private var progress: Double { test.target > 0 ? min(Double(test.nightsLogged) / Double(test.target), 1) : 0 }

    private var done: Bool { test.nightsLogged >= test.target }

    private var header: some View {
        SummaryHeader(eyebrow: "Nights logged", value: "\(min(test.nightsLogged, test.target)) of \(test.target)",
                      status: SummaryStatus(text: done ? "Done" : "\(test.target - test.nightsLogged) to go", accent: done ? .mint : .yellow),
                      line: done ? "You've logged enough nights for a solid answer. It keeps updating as you log more."
                                 : "Does a later coffee cost you sleep? Your own nights answer it.",
                      accent: .yellow, info: Topic.cutoffTest.explanation) {
            SummaryMeter(fraction: progress, accent: .yellow, caption: "\(test.nightsLogged) of \(test.target) nights logged")
        }
    }

    // MARK: Result

    /// Groups with caffeine and enough nights to compare.
    private var comparable: [CaffeineCutoffTest.Group] {
        test.groups.filter { $0.label != "No caffeine" && $0.nights >= HabitEffect.minimumNights }
    }

    private var conclusion: (title: String, detail: String) {
        let groups = comparable
        guard groups.count >= 2, let early = groups.first, let late = groups.last else {
            return ("Not enough to compare yet",
                    "We need at least \(HabitEffect.minimumNights) nights in two different last-caffeine groups. Keep logging your caffeine at the real time you have it.")
        }
        let diff = early.averageAsleep - late.averageAsleep
        let earlyLabel = early.label.lowercased()
        let lateLabel = late.label.lowercased()
        let caveat = test.nightsLogged < test.target ? " This is an early result; it firms up as you log more." : ""
        let n = " (\(early.nights) and \(late.nights) nights)"
        let gap = Self.meaningfulGap(nights: min(early.nights, late.nights))
        if diff >= gap {
            return ("Late caffeine costs you sleep",
                    "When your last caffeine is \(lateLabel), you sleep about \(Clock.duration(diff)) less than when it's \(earlyLabel)\(n). \(model.caffeineCutoffShown.map { "Your \(Clock.format($0)) cutoff is worth keeping." } ?? "Keeping caffeine small and early is worth it.")\(caveat)")
        }
        if diff <= -gap {
            return ("No cost from later caffeine so far",
                    "You've actually slept a bit more on later-caffeine days\(n). Other things probably matter more for you, like bedtime. Caffeine can still make sleep lighter without making it shorter.\(caveat)")
        }
        return ("About the same so far",
                "With this many nights, a difference under about \(gap) minutes could just be chance, and yours is \(abs(diff)) minutes, whether your last caffeine is \(earlyLabel) or \(lateLabel)\(n). Caffeine can still make sleep lighter without making it shorter.\(caveat)")
    }

    /// The smallest difference in average sleep that stands out from
    /// ordinary swings (Liu 10): sleep varies about an hour night to night,
    /// so with few nights per group only a big gap means much. About 45
    /// minutes at 5 nights, 30 at 10, 25 at 20, 20 from about 30, in 5s.
    static func meaningfulGap(nights: Int) -> Int {
        let raw = 60 * (2 / Double(max(nights, 1))).squareRoot() * 1.2
        return max(20, Int((raw / 5).rounded()) * 5)
    }

    private var selectedGroup: CaffeineCutoffTest.Group? {
        guard let selected else { return nil }
        return test.groups.first { $0.label == selected }
    }

    private func readout(for group: CaffeineCutoffTest.Group?) -> (title: String, value: String, detail: String) {
        guard let g = group else {
            let best = test.groups.max { $0.averageAsleep < $1.averageAsleep }
            return ("Average sleep by last caffeine", best.map { "Best: \($0.label.lowercased())" } ?? "No nights yet",
                    best.map { "\(Clock.duration($0.averageAsleep)) on average over \($0.nights) nights." } ?? "Log caffeine to start the test.")
        }
        var detail = "\(g.nights) night\(g.nights == 1 ? "" : "s") in this group."
        if let first = test.groups.first, first.label != g.label {
            let d = first.averageAsleep - g.averageAsleep
            let other = first.label == "No caffeine" ? "on nights with no caffeine" : "when you stop \(first.label.lowercased())"
            if abs(d) < 5 { detail += " About the same as \(other)." }
            else { detail += " \(Clock.duration(abs(d))) \(d > 0 ? "less" : "more") than \(other)." }
        }
        if g.nights < HabitEffect.minimumNights { detail += " Too few nights to trust yet." }
        return ("Last caffeine \(g.label.lowercased())", "\(Clock.duration(g.averageAsleep)) asleep", detail)
    }

    private var resultCard: some View {
        Card {
            let c = conclusion
            Text(c.title).font(.cardTitle).accessibilityAddTraits(.isHeader)
            Text(c.detail).font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            if !test.groups.isEmpty {
                let r = readout(for: selectedGroup)
                ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: .yellow,
                             onClear: selected == nil ? nil : { selected = nil },
                             detailSlots: test.groups.map { readout(for: $0).detail } + [readout(for: nil).detail])
                CutoffBarChart(groups: test.groups, selected: selectedGroup?.label, selection: $selected)
                    .frame(height: 190)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Average sleep by time of last caffeine: "
                                        + test.groups.map { "\($0.label), \(Clock.duration($0.averageAsleep)) over \($0.nights) nights" }.joined(separator: "; ") + ".")
                    .accessibilityChartDescriptor(CategoryChartDescriptor(
                        title: "Average sleep by time of last caffeine", seriesName: "Last caffeine", yTitle: "Average sleep",
                        points: test.groups.map { ($0.label, Double($0.averageAsleep)) },
                        yLabel: { Clock.duration(Int($0.rounded())) }))
                ScrubHint(each: "group")
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.secondary).fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(Accent.yellow.tint(scheme), in: Circle())
            Text(text).font(.bodyText).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CutoffBarChart: View {
    let groups: [CaffeineCutoffTest.Group]
    let selected: String?
    @Binding var selection: String?
    @Environment(\.colorScheme) private var scheme

    private func color(_ g: CaffeineCutoffTest.Group) -> Color {
        let base = Accent.yellow.fill(scheme)
        guard let selected else { return base }
        return g.label == selected ? base : base.opacity(0.35)
    }

    private var yMax: Double { max(Double(groups.map(\.averageAsleep).max() ?? 480) / 60 + 1, 9) }

    var body: some View {
        Chart {
            ForEach(groups, id: \.label) { g in
                BarMark(x: .value("Last caffeine", g.label), y: .value("Hours asleep", Double(g.averageAsleep) / 60), width: .ratio(0.6))
                    .foregroundStyle(color(g))
                    .cornerRadius(8)
                    .annotation(position: .top) {
                        Text(Clock.duration(g.averageAsleep)).font(.chartLabel(size: 12, weight: .bold)).secondaryText()
                    }
            }
        }
        .chartScrub($selection, snapped: selected, steps: groups.map(\.label))
        .chartYScale(domain: 0.0...yMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 4.0, 8.0]) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let h = value.as(Double.self) { Text("\(Int(h))h") }
                }
            }
        }
    }
}
