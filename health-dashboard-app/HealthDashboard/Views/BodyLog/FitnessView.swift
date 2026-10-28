import SwiftUI
import Charts
import HealthCore

/// Cardio fitness: VO2 max, fitness age and a scrubbable history.
struct FitnessView: View {
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
                if points.count >= 2 { historyCard }
                if !hidesTargets { tipsCard }
                ageCard
            } else {
                Card(accent: .mint) {
                    Text("No VO\u{2082} max yet").font(.scaled(size: 18, weight: .bold))
                    Text("Your Apple Watch estimates it during outdoor walks, runs or hikes of 20 minutes or more. It usually appears after a few of those.")
                        .font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
                }
            }
            HowWeGotThisLink(title: "Fitness age",
                             method: "Your Apple Watch estimates VO\u{2082} max from your heart rate and pace on outdoor walks and runs. Fitness age is the age at which an average \(store.data.sex == .female ? "woman" : "man") has your VO\u{2082} max, from population averages that drop about \(store.data.sex == .female ? "0.32" : "0.35") points a year from age 20. The line doesn't go below 20, so anything fitter than an average 20-year-old shows as \u{201C}Under 20\u{201D}. The level compares you with the average for your age, on the same line, so the two always agree; without your age there's no level, only the fitness age.")
        }
    }

    // MARK: Hero

    private func hero(vo2: Double) -> some View {
        Card(padding: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", vo2)).font(.scaledNumber(48)).foregroundStyle(Accent.mint.ink(scheme))
                    HStack(spacing: 0) {
                        Text("VO\u{2082} MAX").font(.scaled(size: 12, weight: .bold)).secondaryText()
                        InfoButton(title: "VO\u{2082} max",
                                   meaning: "How much oxygen your body can use during hard exercise, in ml per kg per minute. It's the best single measure of how fit your heart and lungs are.",
                                   forYou: "Higher is better. It rises with regular cardio (brisk walks, runs, cycling) and drops with time off. It changes over weeks, not days.")
                            .padding(.vertical, -12)
                    }
                    Text(model.fitnessLevelShown ?? "").font(.scaled(size: 13, weight: .semibold)).secondaryText()
                }
                Spacer()
                if let fa = model.fitnessAgeText {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 0) {
                            Text("FITNESS AGE").font(.scaled(size: 12, weight: .bold)).secondaryText()
                            InfoButton(topic: .fitnessAge).padding(.vertical, -12)
                        }
                        Text(fa).font(.scaledNumber(fa.count > 3 ? 28 : 40))
                        if age > 0 {
                            Text("Real age \(age)").font(.scaled(size: 13, weight: .semibold)).secondaryText()
                        }
                    }
                }
            }
            if let fa = model.fitnessAge, age > 0 {
                Text(ageComparison(fitnessAge: fa, vo2: vo2))
                    .font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
            }
            if let peak = model.vo2MaxPeak, peak.value > vo2 + 0.5 {
                Text("Your peak was \(String(format: "%.1f", peak.value)) in \(peak.date.formatted(.dateTime.year()))." + (hidesTargets ? "" : " VO\u{2082} max comes back fast, often 3\u{2013}5 points in 8 weeks of regular cardio."))
                    .font(.scaled(size: 14)).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ageComparison(fitnessAge fa: Int, vo2: Double) -> String {
        if FitnessAge.isTopOfChart(vo2Max: vo2, sex: store.data.sex) {
            return age <= 20 ? "Your heart and lungs are at least as fit as an average 20-year-old's." : "Your heart and lungs are fitter than an average 20-year-old's, younger than your \(age) years."
        }
        let d = fa - age
        if d <= -2 { return "Your heart and lungs are as fit as an average \(fa)-year-old's, \(abs(d)) years younger than you." }
        if d < 2 { return "Your fitness matches your age." + (hidesTargets ? "" : " Regular cardio a few times a week will push it lower.") }
        return "Your fitness matches an average \(fa)-year-old's, \(d) years older than you." + (hidesTargets ? "" : " Very common for students; it improves quickly with regular brisk walks or runs.")
    }

    // MARK: History

    private var shown: Point? {
        guard let s = selected else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) }
    }

    private var readoutDetail: String {
        guard let p = shown else { return "" }
        let fa = FitnessAge.isTopOfChart(vo2Max: p.value, sex: store.data.sex) ? "under 20" : "\(FitnessAge.estimate(vo2Max: p.value, sex: store.data.sex))"
        var text = "Fitness age then: \(fa)."
        if let first = points.first, p.date != first.date {
            let diff = p.value - first.value
            text += " " + (diff >= 0 ? String(format: "Up %.1f", diff) : String(format: "Down %.1f", -diff)) + " since \(first.date.formatted(.dateTime.month(.abbreviated).year()))."
        }
        if p.date == model.vo2MaxPeak?.date { text += " Your peak." }
        return text
    }

    private var historyCard: some View {
        Card {
            SectionLabel(text: "VO\u{2082} max since \(points.first?.date.formatted(.dateTime.year()) ?? "")")
            if let p = shown {
                ChartReadout(title: selected == nil ? "Latest \u{00B7} \(p.date.formatted(.dateTime.month(.abbreviated).year()))" : p.date.formatted(.dateTime.month(.abbreviated).day().year()),
                             value: String(format: "%.1f", p.value), detail: readoutDetail, accent: .mint)
            }
            chart
            ScrubHint()
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
        .chartScrub($selected)
        .frame(height: 170)
        .accessibilityLabel("VO2 max history: " + points.map { "\($0.date.formatted(.dateTime.month(.abbreviated).year())) \(String(format: "%.1f", $0.value))" }.joined(separator: ", "))
    }

    // MARK: Tips and age

    private var tipsCard: some View {
        Card(accent: .mint) {
            SectionLabel(text: "What moves it", accent: .mint)
            Text(tipText)
                .font(.scaled(size: 14)).fixedSize(horizontal: false, vertical: true)
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
        if level.hasPrefix("Well above") || level.hasPrefix("Above") {
            return "You\u{2019}re already fitter than average. Keeping up what you do holds it there; hills and short faster bursts can push it further."
        }
        if level.hasPrefix("About") {
            return "Regular brisk walks, runs or bike rides move it up. Hills and short faster bursts help most. Brisk means you can talk but not sing."
        }
        return "Brisk walks, runs or bike rides a few times a week bring it up, and it starts to move within weeks. Brisk means you can talk but not sing."
    }

    private var ageCard: some View {
        Card {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(age == 0 ? "Add your age (optional)" : "Your age").font(.scaled(size: 15, weight: .bold))
                    Text("Compares your fitness with your own age group. Stays on your phone.")
                        .font(.scaled(size: 12)).secondaryText().fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Picker("Age", selection: ageBinding) {
                    Text("Not set").tag(0)
                    ForEach(13...90, id: \.self) { a in Text("\(a)").tag(a) }
                }
                .pickerStyle(.menu)
                .tint(Accent.mint.ink(scheme))
            }
            .frame(minHeight: 44)
            Picker("Compared with", selection: $store.data.sex) {
                Text("Women").tag(FitnessAge.Sex.female)
                Text("Men").tag(FitnessAge.Sex.male)
            }
            .pickerStyle(.segmented)
        }
    }
}
