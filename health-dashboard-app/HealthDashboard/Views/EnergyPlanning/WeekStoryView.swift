import SwiftUI
import HealthCore

/// "Your week" as a story (D-P1): five cards she swipes through (best
/// night, energy, caffeine, pack week, one thing to try), new each Sunday
/// evening. The day-by-day recap is one tap down from the last card.
/// Every card says what happened, never what caused it.
struct WeekStoryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var page = 0

    var body: some View {
        let p = Palette(scheme: scheme)
        Group {
            if let story = model.weekStory, let recap = model.weekRecap {
                let days = model.lastWeek.sorted { $0.date < $1.date }
                VStack(spacing: Space.s) {
                    SampleDataBanner()
                        .padding(.horizontal, Space.xl)
                    TabView(selection: $page) {
                        bestNightCard(story, days: days).tag(0)
                        energyCard(story, days: days).tag(1)
                        caffeineCard(story, days: days).tag(2)
                        fourthCard(days: days).tag(3)
                        goalCard(recap).tag(4)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            } else {
                Screen(title: "Your week", accent: .indigo) {
                    Card(accent: .indigo) {
                        Text("Not enough days yet").font(.section)
                        Text("Your week needs at least 3 days with a recorded night. Keep wearing your Watch to bed.")
                            .font(.bodyText).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                p.background
                p.glow(accent(page)).frame(height: 460)
            }
            .ignoresSafeArea()
        }
        .foregroundStyle(p.primary)
        .navigationTitle(weekTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: page)
    }

    private func accent(_ page: Int) -> Accent {
        [.purple, .mint, .yellow, model.packWeek != nil ? .pink : .orange, .indigo][min(max(page, 0), 4)]
    }

    /// "Your week · Oct 18–24"
    private var weekTitle: String {
        let days = model.lastWeek.map(\.date).sorted()
        guard let first = days.first, let last = days.last else { return "Your week" }
        let sameMonth = Calendar.current.isDate(first, equalTo: last, toGranularity: .month)
        let end = sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
        return "Your week \u{00B7} \(first.formatted(.dateTime.month(.abbreviated).day()))\u{2013}\(end)"
    }

    private func weekday(_ date: Date) -> String { date.formatted(.dateTime.weekday(.wide)) }
    private func letter(_ date: Date) -> String { date.formatted(.dateTime.weekday(.narrow)) }
    private func nightBefore(_ date: Date) -> Date { Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date }

    // MARK: Cards

    private func bestNightCard(_ s: WeekStory, days: [DaySummary]) -> some View {
        let best = s.bestNight
        let bars = days.map { StoryBar(label: letter(nightBefore($0.date)), value: Double($0.asleep), highlighted: $0.date == best.date) }
        return StoryCard(index: 0, kicker: "Best night", accent: .purple,
                         headline: "\(weekday(nightBefore(best.date))) night",
                         value: Clock.duration(best.asleep), unit: "asleep",
                         line: "In bed at \(Clock.format(best.bedtime)), up at \(Clock.format(best.wake)). Your nights averaged \(Clock.duration(s.averageAsleep)).",
                         bars: bars,
                         chartLabel: "Time asleep each night: " + days.map { "\(weekday(nightBefore($0.date))) \(Clock.duration($0.asleep))" }.joined(separator: ", "))
    }

    private func energyCard(_ s: WeekStory, days: [DaySummary]) -> some View {
        var line = "Highest on \(weekday(s.bestDay.date)) (\(s.bestDay.energy)), lowest on \(weekday(s.lowestDay.date)) (\(s.lowestDay.energy))."
        if let wd = s.weekdayEnergy, let we = s.weekendEnergy {
            line += " Weekdays averaged \(wd), the weekend \(we)."
        }
        let bars = days.map { StoryBar(label: letter($0.date), value: Double($0.energy), highlighted: $0.date == s.bestDay.date) }
        return StoryCard(index: 1, kicker: "Energy", accent: .mint,
                         headline: "Your energy pattern",
                         value: "\(s.averageEnergy)", unit: "week average",
                         line: line + " Estimated from your sleep.",
                         bars: bars,
                         chartLabel: "Energy score by day: " + days.map { "\(weekday($0.date)) \($0.energy)" }.joined(separator: ", "))
    }

    private func caffeineCard(_ s: WeekStory, days: [DaySummary]) -> some View {
        let c = s.caffeine
        let line: String
        if c.days == 0 {
            line = "No caffeine logged this week."
        } else {
            var text = "Caffeine on \(c.days) of \(days.count) days"
            if let last = c.typicalLast { text += ", usually last at \(Clock.format(last))" }
            text += "."
            if let cutoff = model.caffeineCutoffShown {
                text += c.daysAfterCutoff == 0
                    ? " Every day stayed before your \(Clock.format(cutoff)) cutoff."
                    : " \(c.daysAfterCutoff) \(c.daysAfterCutoff == 1 ? "day" : "days") went past your \(Clock.format(cutoff)) cutoff."
            }
            line = text
        }
        let bars = days.map { StoryBar(label: letter($0.date), value: Double($0.caffeineMg), highlighted: model.caffeineTooLate($0)) }
        return StoryCard(index: 2, kicker: "Caffeine", accent: .yellow,
                         headline: "Your caffeine habit",
                         value: c.days == 0 ? "None" : "\(c.averageMg) mg", unit: c.days == 0 ? nil : "on caffeine days",
                         line: line, bars: bars, highlightAccent: .coral,
                         chartLabel: "Caffeine by day: " + days.map { "\(weekday($0.date)) \($0.caffeineMg) milligrams" }.joined(separator: ", "))
    }

    /// The pack week on the pill; her mornings otherwise.
    @ViewBuilder
    private func fourthCard(days: [DaySummary]) -> some View {
        if let w = model.packWeek {
            let length = store.data.packLength
            let headline = w.breakDays == days.count ? "Break week" : w.breakDays > 0 ? "Pills and break" : "Active pills"
            StoryCard(index: 3, kicker: "Pack week", accent: .pink,
                      headline: headline,
                      value: "\(w.firstDay)\u{2013}\(w.lastDay)", unit: "of \(length)",
                      line: packLine(w), chartLabel: nil) {
                PackDots(days: days.map(\.date), model: model)
            }
        } else {
            let checkIns = days.compactMap(\.checkIn)
            let avg = checkIns.isEmpty ? nil : checkIns.reduce(0, +) / Double(checkIns.count)
            StoryCard(index: 3, kicker: "Mornings", accent: .orange,
                      headline: "How your mornings felt",
                      value: avg.map { String(format: "%.1f", $0) } ?? "\u{2013}", unit: avg == nil ? nil : "of 5 awake",
                      line: checkIns.isEmpty ? "No check-ins this week. Ten seconds each morning teaches the app your sleep need."
                                             : "You checked in \(checkIns.count) of \(days.count) mornings.",
                      bars: days.map { StoryBar(label: letter($0.date), value: $0.checkIn ?? 0, highlighted: false) },
                      chartLabel: "Morning check-ins: " + days.map { "\(weekday($0.date)) \($0.checkIn.map { String(Int($0)) } ?? "none")" }.joined(separator: ", "))
        }
    }

    /// "6 of 7 pills marked taken. Your break starts Thursday."
    private func packLine(_ w: PackWeek) -> String {
        var line = w.pillDays == 0 ? "No pills this week." : "\(w.taken) of \(w.pillDays) pills marked taken."
        if let next = w.next {
            let when = weekday(next.date)
            line += next.kind == .breakStarts ? " Your break starts \(when)." : " Your new pack starts \(when)."
        }
        return line
    }

    private func goalCard(_ recap: WeekRecap) -> some View {
        let g = model.weekGoal(recap, need: model.sleepNeed.minutes)
        let isOn = store.data.weeklyGoal == g.title
        return StoryCard(index: 4, kicker: "One thing to try", accent: .indigo,
                         headline: g.title, value: nil, unit: nil, line: g.detail, chartLabel: nil) {
            VStack(spacing: Space.s) {
                PrimaryButton(title: isOn ? "Your goal this week" : "Make it my goal", accent: .indigo, done: isOn) {
                    store.data.weeklyGoal = isOn ? nil : g.title
                }
                .accessibilityAddTraits(isOn ? .isSelected : [])
                NavigationLink { WeekRecapView() } label: {
                    Text("See every day")
                        .font(.bodyEmphasis)
                        .foregroundStyle(Accent.indigo.ink(scheme))
                        .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One bar of a card's small week chart.
private struct StoryBar: Identifiable {
    var id: String { label + "\(value)" }
    var label: String
    var value: Double
    var highlighted: Bool
}

/// A story card: "2 of 5 · Energy", a headline, the number, one sentence,
/// and a small week chart (or other content) underneath.
private struct StoryCard<Extra: View>: View {
    var index: Int
    var kicker: String
    var accent: Accent
    var headline: String
    var value: String?
    var unit: String?
    var line: String
    var bars: [StoryBar] = []
    var highlightAccent: Accent? = nil
    /// The chart's one-sentence VoiceOver summary.
    var chartLabel: String?
    @ViewBuilder var extra: Extra
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                CapsLabel("\(index + 1) of 5 \u{00B7} \(kicker)", color: accent.ink(scheme))
                Text(headline)
                    .font(.detailTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(value).font(.display).lineLimit(1).minimumScaleFactor(0.6)
                        if let unit { Text(unit).font(.bodyEmphasis).foregroundStyle(p.secondary) }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(line)
                    .font(.bodyText)
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !bars.isEmpty {
                    WeekBars(bars: bars, accent: accent, highlight: highlightAccent ?? accent)
                        .frame(height: 120)
                        .padding(.top, Space.s)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(chartLabel ?? "")
                }
                extra
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous).strokeBorder(p.cardBorder))
            .padding(.horizontal, Space.xl)
            .padding(.bottom, 56)
        }
    }
}

extension StoryCard where Extra == EmptyView {
    init(index: Int, kicker: String, accent: Accent, headline: String, value: String?, unit: String?, line: String,
         bars: [StoryBar] = [], highlightAccent: Accent? = nil, chartLabel: String?) {
        self.init(index: index, kicker: kicker, accent: accent, headline: headline, value: value, unit: unit, line: line,
                  bars: bars, highlightAccent: highlightAccent, chartLabel: chartLabel) { EmptyView() }
    }
}

/// Seven bars with a day letter under each; highlighted bars in full colour.
private struct WeekBars: View {
    var bars: [StoryBar]
    var accent: Accent
    var highlight: Accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let top = max(bars.map(\.value).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: Space.s) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, b in
                VStack(spacing: Space.xs) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: Radius.mark, style: .continuous)
                                .fill(b.highlighted ? highlight.fill(scheme) : accent.fill(scheme).opacity(0.45))
                                .frame(height: max(geo.size.height * b.value / top, b.value > 0 ? 4 : 0))
                        }
                    }
                    Text(b.label).font(.secondary).foregroundStyle(Palette(scheme: scheme).secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The week's pills as dots: filled taken, ringed not marked, faint on
/// break days.
private struct PackDots: View {
    var days: [Date]
    var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pink = Accent.pink
        HStack(spacing: Space.s) {
            ForEach(days, id: \.self) { day in
                let pillDay = model.pillPack?.isPillDay(day) ?? false
                let taken = pillDay && model.isPillTaken(on: day)
                VStack(spacing: Space.xs) {
                    Circle()
                        .fill(taken ? pink.fill(scheme) : (pillDay ? Color.clear : pink.track(scheme)))
                        .overlay(Circle().strokeBorder(pillDay ? pink.fill(scheme) : .clear, lineWidth: 2))
                        .frame(width: 28, height: 28)
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.secondary).foregroundStyle(Palette(scheme: scheme).secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Space.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days.map { day -> String in
            let name = day.formatted(.dateTime.weekday(.wide))
            guard model.pillPack?.isPillDay(day) ?? false else { return "\(name) break" }
            return "\(name) \(model.isPillTaken(on: day) ? "taken" : "not marked")"
        }.joined(separator: ", "))
    }
}
