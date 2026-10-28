import SwiftUI
import HealthCore

/// The Sleep tab, summary first: last night, her best sleep times, the last
/// week at a glance, then one row per detail (stages, history, need and
/// debt, weekend shift) and the Health guide.
struct SleepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedDay: Date? = nil

    var body: some View {
        Screen(title: "Sleep", accent: .purple) {
            TabHeader("Sleep")
            SampleDataBanner()
            if model.lastNightIsFresh {
                lastNightCard
            } else {
                noSleepBar
            }
            BestTimesCard()
            weekCard
            rows
            Card(density: .compact) {
                LearnMoreRow("Learn more about trouble sleeping", article: .troubleSleeping, accent: .purple)
            }
        }
    }

    // MARK: Last night

    /// "34 min short of your 7h 55m need", "Right on your 7h 55m need".
    private var needLine: String {
        let need = model.sleepNeed.minutes
        let gap = model.lastNight.asleep - need
        if gap < -15 { return "\(Clock.duration(-gap)) short of your \(Clock.duration(need)) need" }
        if gap > 15 { return "\(Clock.duration(gap)) more than your \(Clock.duration(need)) need" }
        return "Right on your \(Clock.duration(need)) need"
    }

    /// Dial beside the times when they fit; at large text sizes the times
    /// go under the dial.
    private var lastNightCard: some View {
        Card {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.l) {
                    lastNightDial
                    lastNightStats
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Space.m) {
                    lastNightDial.frame(maxWidth: .infinity)
                    lastNightStats
                }
            }
        }
    }

    private var lastNightDial: some View {
        let night = model.lastNight
        return SleepArcDial(start: night.onset, end: night.wake, size: 132, lineWidth: 12,
                            colors: [Accent.purple.ink(scheme), Accent.purple.fill(scheme)],
                            label: Clock.duration(night.asleep), labelSize: 22,
                            caption: "last night", showHours: true)
    }

    private var lastNightStats: some View {
        let night = model.lastNight
        return VStack(alignment: .leading, spacing: Space.m) {
            statBlock("Fell asleep", night.onset)
            statBlock("Woke up", night.wake)
            Text(needLine)
                .font(.secondary)
                .foregroundStyle(Palette(scheme: scheme).secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statBlock(_ title: String, _ time: Minutes) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            CapsLabel(title, isHeader: false)
            ClockText(minutes: time, role: .numberM)
        }
        .accessibilityElement(children: .combine)
    }

    /// No night ended this morning: one line that opens how to get it recorded.
    @State private var showingNoSleep = false

    private var noSleepBar: some View {
        CalloutBar(text: "No sleep recorded last night", systemImage: "moon.zzz", accent: .purple) {
            showingNoSleep = true
        }
        .navigationDestination(isPresented: $showingNoSleep) { AccuracyTipsView() }
    }

    // MARK: Last 7 nights

    private var weekNights: [NightRecord] { model.sleepHistoryNights(days: 7) }

    private var selectedNight: NightRecord? {
        guard let selectedDay else { return nil }
        return weekNights.min { abs($0.wakeDay.timeIntervalSince(selectedDay)) < abs($1.wakeDay.timeIntervalSince(selectedDay)) }
    }

    private func vsNeed(_ asleep: Int) -> String {
        let gap = asleep - model.sleepNeed.minutes
        if abs(gap) <= 10 { return "about your need" }
        return gap < 0 ? "\(Clock.duration(-gap)) under your need" : "\(Clock.duration(gap)) over your need"
    }

    private func nightTitle(_ day: Date) -> String {
        let night = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        return "Night of " + night.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var weekAverage: Int { Int((weekNights.map { Double($0.asleepMinutes) }.mean ?? 0).rounded()) }
    private var weekMet: Int { weekNights.filter { model.metNeed($0) }.count }

    private var weekSummaryDetail: String {
        "\(weekMet) of \(weekNights.count) nights reached your \(Clock.duration(model.sleepNeed.minutes)) need."
    }

    private func nightDetail(_ n: NightRecord) -> String {
        "Bed \(Clock.format(n.bedtime)) \u{00B7} up \(Clock.format(n.wake)) \u{00B7} \(vsNeed(n.asleepMinutes))"
    }

    @ViewBuilder
    private var weekReadout: some View {
        let slots = [weekSummaryDetail] + weekNights.map(nightDetail)
        if let n = selectedNight {
            ChartReadout(title: nightTitle(n.wakeDay) + " \u{00B7} asleep", value: Clock.duration(n.asleepMinutes),
                         detail: nightDetail(n), accent: model.metNeed(n) ? .purple : .coral,
                         onClear: { selectedDay = nil }, detailSlots: slots)
        } else {
            ChartReadout(title: "Last 7 nights \u{00B7} average", value: Clock.duration(weekAverage),
                         detail: weekSummaryDetail, accent: .purple, detailSlots: slots)
        }
    }

    @ViewBuilder
    private var weekCard: some View {
        if !weekNights.isEmpty {
            let met = Set(weekNights.filter { model.metNeed($0) }.map { Calendar.current.startOfDay(for: $0.wakeDay) })
            Card {
                weekReadout
                HistoryBars(nights: weekNights, need: model.sleepNeed.minutes, metDays: met, exampleDays: [],
                            selected: selectedNight?.wakeDay,
                            selection: $selectedDay.snapping { d in
                                weekNights.min { abs($0.wakeDay.timeIntervalSince(d)) < abs($1.wakeDay.timeIntervalSince(d)) }?.wakeDay
                            },
                            barWidth: 22)
                    .frame(height: 150)
                NeedLegend(need: model.sleepNeed.minutes)
            }
        }
    }

    // MARK: Rows

    /// Deep and REM last night, the stages a row can name in one line.
    private var stagesNote: String {
        let m = model.lastNight.stageMinutes
        return "Deep \(Clock.duration(m[.deep] ?? 0)) \u{00B7} REM \(Clock.duration(m[.rem] ?? 0))"
    }

    private var weekendShift: Int? {
        guard !model.workNights.isEmpty, !model.freeNights.isEmpty else { return nil }
        return model.chronotype?.socialJetlag
    }

    private var rows: some View {
        let debt = model.sleepDebt
        return RowCard {
            if model.lastNightIsFresh {
                MetricRow(title: "Sleep stages", note: stagesNote, systemImage: "chart.bar.doc.horizontal.fill", accent: .purple) {
                    SleepStagesView()
                }
                RowDivider()
            }
            MetricRow(title: "Week & month", note: "Every night and your averages",
                      value: model.sleepRegularityScore.map { "\($0)" },
                      verdict: model.sleepRegularityScore.map { _ in RowVerdict(text: "Regularity", accent: .purple) },
                      systemImage: "chart.bar.fill", accent: .purple) {
                SleepHistoryView()
            }
            RowDivider()
            MetricRow(title: "Sleep need & debt",
                      note: "Need \(Clock.duration(model.sleepNeed.minutes)) \u{00B7} tonight \(model.tonightNeedText)",
                      value: debt >= 15 ? Clock.duration(debt) : nil,
                      verdict: RowVerdict(text: debt >= 15 ? "Debt" : "No debt", accent: debt >= 60 ? .coral : .mint),
                      systemImage: "bed.double.fill", accent: .purple) {
                SleepNeedView()
            }
            if let shift = weekendShift {
                RowDivider()
                MetricRow(title: "Weekend shift", note: "Free nights against school nights",
                          value: Clock.duration(shift),
                          verdict: RowVerdict(text: "Later", accent: shift >= 60 ? .coral : .mint),
                          systemImage: "calendar", accent: .indigo) {
                    ChronotypeView()
                }
            }
            if model.daysUntilFallBack <= 28 {
                RowDivider()
                MetricRow(title: "Clocks go back \(model.nextFallBack.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))",
                          note: "What it means for your sleep",
                          systemImage: "clock.arrow.circlepath", accent: .orange) {
                    TimeChangeView()
                }
            }
        }
    }
}

/// The dashed need line's key, under a sleep chart instead of on the plot.
struct NeedLegend: View {
    var need: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        HStack(spacing: Space.s) {
            Capsule()
                .stroke(p.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 18, height: 2)
            Text("Your need \(Clock.duration(need))")
            Spacer(minLength: Space.s)
            Circle().fill(Accent.coral.fill(scheme)).frame(width: 8, height: 8)
            Text("Under it")
        }
        .font(.secondary)
        .foregroundStyle(p.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dashed line: your need, \(Clock.duration(need)). Coral bars are nights under it.")
    }
}
