import SwiftUI
import Charts
import HealthCore

/// Cardio fitness: VO2 max, fitness age and a scrubbable history.
struct FitnessView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selected: Date? = nil

    /// Her age, if she chose to add it (0 = not set). Saved with her settings.
    private var age: Int { store.data.ageYears ?? 0 }
    private var ageBinding: Binding<Int> {
        Binding(get: { store.data.ageYears ?? 0 }, set: { store.data.ageYears = $0 > 0 ? $0 : nil })
    }
    private var hidesTargets: Bool { model.hidesActivityNumbers }

    private struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
    }

    private var points: [Point] {
        model.vo2MaxHistory.sorted { $0.date < $1.date }.map { Point(date: $0.date, value: $0.value) }
    }

    var body: some View {
        Screen(title: "Fitness", accent: .mint) {
            SampleDataBanner()
            if let vo2 = model.vo2Max {
                hero(vo2: vo2)
                // Under eating-disorder history: the number only. No fitness
                // age, history line or age comparison (round 3, H6).
                if points.count >= 2 && !hidesTargets { historyCard }
                if !hidesTargets {
                    tipsCard
                    ageCard
                }
            } else {
                Card(accent: .mint) {
                    Text("No VO\u{2082} max yet").font(.cardTitle)
                    Text("Your Apple Watch estimates it during outdoor walks, runs or hikes of 20 minutes or more. It usually appears after a few of those.")
                        .font(.bodyText).secondaryText().fixedSize(horizontal: false, vertical: true)
                }
            }
            HowWeGotThisLink(title: "Fitness age",
                             method: "Your Apple Watch estimates VO\u{2082} max from your heart rate and pace on outdoor walks and runs. Estimates like this are often off by 5 points or more, so treat it as a rough guide and watch the trend. Fitness age is the age at which a typical woman has your VO\u{2082} max. It uses the FRIEND registry of treadmill tests in US women (2015), the same kind of reference Apple uses: the middle value for women in their 20s is 37.6, in their 30s 30.2, 40s 26.7, 50s 23.4, 60s 20.0 and 70s 18.3, joined into a smooth line. The line is flat below 25, so anything at or above the middle of women in their 20s shows as \u{201C}Under 25\u{201D}. Because of the Watch\u{2019}s error it\u{2019}s shown as a range: the fitness ages for your estimate 5 points higher and 5 points lower. The level compares you with women in your age group (women in their 20s if you\u{2019}re younger than 20): the middle half of them is \u{201C}about average\u{201D}, the top quarter \u{201C}above average\u{201D} and the bottom quarter \u{201C}below average\u{201D}. Without your age there\u{2019}s no level, only the fitness age.")
        }
    }

    // MARK: Hero

    private func hero(vo2: Double) -> some View {
        Card {
            // VO2 max above fitness age at large text sizes; numbers never
            // break across lines ("38 / .2").
            AdaptiveStack(spacing: 12, alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", vo2)).font(.display).foregroundStyle(Accent.mint.ink(scheme))
                        .keepsOnOneLine()
                    HStack(spacing: 0) {
                        Text("VO\u{2082} MAX").font(.secondary).fontWeight(.bold).secondaryText()
                        InfoButton(title: "VO\u{2082} max",
                                   meaning: "How much oxygen your body can use during hard exercise, in ml per kg per minute. It's the best single measure of how fit your heart and lungs are.",
                                   forYou: "Higher is better. It rises with regular cardio (brisk walks, runs, cycling) and drops with time off. It changes over weeks, not days.")
                            .padding(.vertical, -12)
                    }
                    if hidesTargets {
                        // No "below average" ranking with an eating-disorder history.
                        HStack(spacing: 0) {
                            Text("Your Watch\u{2019}s latest estimate").font(.secondary).fontWeight(.semibold).secondaryText()
                            InfoButton(explanation: Self.noComparisonsExplanation).padding(.vertical, -12)
                        }
                    } else {
                        Text(model.fitnessLevelShown ?? "").font(.secondary).fontWeight(.semibold).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer() }
                if let fa = model.fitnessAgeText, !hidesTargets {
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                        HStack(spacing: 0) {
                            CapsLabel("Fitness age")
                            InfoButton(topic: .fitnessAge).padding(.vertical, -12)
                        }
                        Text(fa).font(fa.count > 3 ? TypeRole.numberL : TypeRole.display).keepsOnOneLine()
                        if age > 0 {
                            Text("Real age \(age)").font(.secondary).fontWeight(.semibold).secondaryText()
                        }
                    }
                }
            }
            if age > 0, !hidesTargets {
                Text(ageComparison(vo2: vo2))
                    .font(.bodyText).fixedSize(horizontal: false, vertical: true)
            }
            if hidesTargets {
                Text("Shown as a number only, with no rankings or ups and downs. It\u{2019}s a rough estimate from your Watch, not a score to beat.")
                    .font(.bodyText).secondaryText().fixedSize(horizontal: false, vertical: true)
            } else if let peak = model.vo2MaxPeak, peak.value > vo2 + 0.5 {
                Text("Your peak was \(String(format: "%.1f", peak.value)) in \(peak.date.formatted(.dateTime.year())). VO\u{2082} max comes back fast, often 3\u{2013}5 points in 8 weeks of regular cardio.")
                    .font(.bodyText).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Why Fitness shows no comparisons, like the Calories screen explains
    /// why calories are hidden.
    static let noComparisonsExplanation = Explanation(
        id: "fitnessNoComparisons", title: "Why there are no comparisons",
        meaning: "You added eating-disorder history to your health conditions, so the app leaves out rankings like \u{201C}below average\u{201D} and fitness age, your past peak, and ups and downs over time. It also keeps calories, step counts and exercise targets out of sight.",
        forYou: "VO\u{2082} max is shown as a plain number from your Watch. You can change this in Health conditions.")

    /// Her age against the fitness-age range. Below 25 the norms are flat,
    /// so a younger woman is compared as 25 (women in their 20s).
    private func ageComparison(vo2: Double) -> String {
        let range = FitnessAge.range(vo2Max: vo2)
        let compared = max(age, FitnessAge.youngest)
        let group = age < 20 ? "women in their 20s" : "women your age"
        if compared < range.lowerBound {
            return "Your fitness age is above your age: less fit than a typical woman your age for now." + (hidesTargets ? "" : " Very common for students; it improves quickly with regular brisk walks or runs.")
        }
        if compared > range.upperBound {
            return "Your heart and lungs look fitter than a typical woman your age, even allowing for the Watch\u{2019}s error."
        }
        return "Your age is inside your fitness-age range, so your fitness is about typical for \(group)." + (hidesTargets ? "" : " Regular cardio a few times a week will push it lower.")
    }

    // MARK: History

    private var shown: Point? {
        guard let s = selected else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) }
    }

    private var readoutDetail: String {
        guard let p = shown else { return "" }
        var parts: [String] = []
        parts.append("Fitness age then: \(FitnessAge.rangeText(vo2Max: p.value).lowercased()).")
        // No "up/down since" or "your peak" with an eating-disorder history.
        if !hidesTargets {
            if let first = points.first, p.date != first.date {
                let diff = p.value - first.value
                parts.append((diff >= 0 ? String(format: "Up %.1f", diff) : String(format: "Down %.1f", -diff)) + " since \(first.date.formatted(.dateTime.month(.abbreviated).year())).")
            }
            if p.date == model.vo2MaxPeak?.date { parts.append("Your peak.") }
        }
        return parts.joined(separator: " ")
    }

    private var historyCard: some View {
        Card {
            SectionLabel(text: "VO\u{2082} max since \(points.first?.date.formatted(.dateTime.year()) ?? "")")
            if let p = shown {
                ChartReadout(title: selected == nil ? "Latest \u{00B7} \(p.date.formatted(.dateTime.month(.abbreviated).year()))" : p.date.formatted(.dateTime.month(.abbreviated).day().year()),
                             value: String(format: "%.1f", p.value), detail: readoutDetail, accent: .mint,
                             onClear: selected == nil ? nil : { selected = nil })
            }
            chart
            ScrubHint(each: "reading")
        }
    }

    private var yDomain: ClosedRange<Double> {
        let vs = points.map(\.value)
        return ((vs.min() ?? 30) - 3)...((vs.max() ?? 50) + 3)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("VO2 max", p.value))
                    .foregroundStyle(Accent.mint.fill(scheme))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let p = shown {
                RuleMark(x: .value("Date", p.date))
                    .foregroundStyle(Palette(scheme: scheme).tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Date", p.date), y: .value("VO2 max", p.value))
                    .foregroundStyle(Accent.mint.ink(scheme))
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: yDomain)
        .chartScrub($selected, snapped: selected == nil ? nil : shown?.date, steps: points.map(\.date))
        .frame(height: 170)
        .accessibilityChartDescriptor(DateChartDescriptor(
            title: "VO2 max history", seriesName: "VO2 max", yTitle: "VO2 max",
            points: points.map { ($0.date, $0.value) }, yLabel: { String(format: "%.1f", $0) }))
        .accessibilityLabel("VO2 max history: " + points.map { "\($0.date.formatted(.dateTime.month(.abbreviated).year())) \(String(format: "%.1f", $0.value))" }.joined(separator: ", "))
    }

    // MARK: Tips and age

    private var tipsCard: some View {
        Card(accent: .mint) {
            SectionLabel(text: "What moves it", accent: .mint)
            Text(tipText)
                .font(.bodyText).fixedSize(horizontal: false, vertical: true)
            // On hormonal birth control the bleed can't flag under-fuelling
            // (RED-S), so say what to watch for instead (Ruiz F2).
            if let bc = store.birthControl, bc != .copperIUD {
                Text(bc.hasBreakWeek ? CycleCare.packBleedCantShowFuel : CycleCare.methodBleedCantShowFuel)
                    .font(.secondary).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            if !model.hidesEffortTargets {
                LinkRow(title: "Today's energy", subtitle: "When you have the most energy today", systemImage: "bolt.fill", accent: .yellow) {
                    EnergyView()
                }
            }
        }
    }

    /// Matched to where she is now; no targets with an eating-disorder history.
    private var tipText: String {
        if model.hidesEffortTargets {
            return "Moving in ways you enjoy keeps your heart fit. It changes slowly, over weeks, so there\u{2019}s nothing to chase day to day."
        }
        let level = model.fitnessLevel ?? ""
        if level.hasPrefix("Above") {
            return "You\u{2019}re already fitter than average. Keeping up what you do holds it there; hills and short faster bursts can push it further."
        }
        if level.hasPrefix("About") {
            return "Regular brisk walks, runs or bike rides move it up. Hills and short faster bursts help most. Brisk means you can talk but not sing."
        }
        return "Brisk walks, runs or bike rides a few times a week bring it up, and it starts to move within weeks. Brisk means you can talk but not sing."
    }

    private var ageCard: some View {
        Card {
            LabeledControlRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(age == 0 ? "Add your age (optional)" : "Your age").font(.bodyEmphasis)
                    Text("Compares your fitness with women your age. Stays on your phone.")
                        .font(.secondary).secondaryText().fixedSize(horizontal: false, vertical: true)
                }
            } control: {
                Picker("Age", selection: ageBinding) {
                    Text("Not set").tag(0)
                    ForEach(13...90, id: \.self) { a in Text("\(a)").tag(a) }
                }
                .pickerStyle(.menu)
                .tint(Accent.mint.ink(scheme))
                .fixedSize()
            }
            .frame(minHeight: 44)
        }
    }
}
