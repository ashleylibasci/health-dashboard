import SwiftUI
import HealthCore

/// The Sleep tab, summary first: last night, her best sleep times, the last
/// week at a glance, then one row per detail (stages, history, need and
/// debt, weekend shift) and the Health guide.
struct SleepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
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

    /// Dial beside the times and last night against her need; at
    /// accessibility text sizes they go under the dial.
    private var lastNightCard: some View {
        Card {
            if typeSize.isAccessibilitySize {
                lastNightDial.frame(maxWidth: .infinity)
                lastNightStats
            } else {
                HStack(spacing: Space.l) {
                    lastNightDial
                    lastNightStats
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var lastNightDial: some View {
        let night = model.lastNight
        return SleepArcDial(start: night.onset, end: night.wake, size: typeSize.isAccessibilitySize ? 180 : 124, lineWidth: 12,
                            colors: [Accent.purple.ink(scheme), Accent.purple.fill(scheme)],
                            label: Clock.duration(night.asleep), labelSize: 22,
                            caption: "last night", showHours: true)
    }

    private var lastNightStats: some View {
        let night = model.lastNight
        return VStack(alignment: .leading, spacing: Space.s) {
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
                    .frame(height: 100)
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

    private static func average(_ nights: [Chronotype.Night]) -> TimeRange? {
        guard !nights.isEmpty else { return nil }
        let n = Double(nights.count)
        let onset = Double(nights.map(\.onset).reduce(0, +)) / n
        let wake = Double(nights.map(\.wake).reduce(0, +)) / n
        return TimeRange(Int(onset.rounded()), Int(wake.rounded()))
    }

    /// School nights against free nights, in place (the body clock itself
    /// lives on the Body tab).
    @ViewBuilder
    private var weekendRow: some View {
        if let work = Self.average(model.workNights), let free = Self.average(model.freeNights) {
            let shift = model.chronotype?.socialJetlag ?? abs((free.start + free.end) / 2 - (work.start + work.end) / 2)
            RowDivider()
            ExpandRow(title: "Weekend shift", summary: "Free nights \(Clock.duration(shift)) later than school nights",
                      systemImage: "calendar", accent: shift >= 60 ? .coral : .indigo) {
                ShiftBar(title: "School nights", range: work, color: Accent.purple.fill(scheme))
                ShiftBar(title: "Free nights", range: free,
                         color: shift >= 60 ? Accent.coral.fill(scheme) : Accent.purple.ink(scheme).opacity(0.6))
                Text(shift >= 60
                     ? "Like flying a time zone west every weekend. Keeping free days within an hour of school days makes Mondays easier."
                     : "Under an hour, which is the goal. Your body clock stays steady through the week.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Morning daylight against 20 minutes before 11am (H-C5), with a
    /// small ring of progress inside.
    @ViewBuilder
    private var morningLightRow: some View {
        if model.showsMorningLight {
            let got = model.morningDaylightToday, goal = AppModel.morningLightGoal
            RowDivider()
            ExpandRow(title: "Morning light", summary: model.morningLightSummary,
                      systemImage: "sun.max.fill", accent: .yellow) {
                HStack(spacing: Space.m) {
                    Ring(value: Double(got) / Double(goal), accent: .yellow, lineWidth: 6,
                         label: "\(got)", size: 48)
                        .accessibilityHidden(true)
                    Text("20 minutes outside before 11am helps you fall asleep earlier. Morning light moves your body clock earlier, and college schedules pull it later.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "A 20-min nap before 3:10pm won't hurt tonight" (H-C2), from her
    /// wake time and tonight's bedtime; after the cutoff, that it's passed.
    @ViewBuilder
    private var napRow: some View {
        if model.showsNapWindow, let cutoff = model.napCutoff {
            let open = model.now < cutoff
            RowDivider()
            ExpandRow(title: "Nap window",
                      summary: open ? "A \(AppModel.napMinutes)-min nap before \(Clock.format(cutoff)) won\u{2019}t hurt tonight"
                                    : "Past \(Clock.format(cutoff)), a nap would push bedtime later",
                      systemImage: "powersleep", accent: open ? .indigo : .coral) {
                Text("Short naps early in the afternoon help you stay alert. Long naps, or naps late in the day, make it harder to fall asleep at \(Clock.format(model.tonightBedtime)). Keep it to \(AppModel.napMinutes) minutes, start it before \(Clock.format(cutoff)), and set an alarm.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            // How regular this week was, in one word; how far her times
            // moved is one tap down (H-C1).
            MetricRow(title: "Week & month", note: "Every night, how regular",
                      verdict: model.weekSteadiness.map { RowVerdict(text: $0.word, accent: $0.accent) },
                      systemImage: "chart.bar.fill", accent: .purple) {
                SleepHistoryView()
            }
            RowDivider()
            MetricRow(title: "Sleep need & debt",
                      note: "You need \(Clock.duration(model.sleepNeed.minutes)) a night",
                      value: debt >= 15 ? Clock.duration(debt) : nil,
                      verdict: RowVerdict(text: debt >= 15 ? "Debt" : "No debt", accent: debt >= 60 ? .coral : .mint),
                      systemImage: "bed.double.fill", accent: .purple) {
                SleepNeedView()
            }
            weekendRow
            morningLightRow
            napRow
            if model.daysUntilFallBack <= 28 {
                RowDivider()
                MetricRow(title: "Clocks go back \(model.nextFallBack.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))",
                          note: "What it means for your sleep",
                          systemImage: "clock.arrow.circlepath", accent: .orange) {
                    TimeChangeView()
                }
            }
            RowDivider(hasIcon: false)
            LearnMoreRow("Learn more about trouble sleeping", article: .troubleSleeping, accent: .purple)
                .padding(.horizontal, Space.l)
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

/// One sleep window on an 8pm-to-noon track.
private struct ShiftBar: View {
    var title: String
    var range: TimeRange
    var color: Color
    @Environment(\.colorScheme) private var scheme

    private let trackStart = -240   // 8pm the evening before
    private let trackLength = 960.0 // to noon

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                // With am/pm: "1:22" alone is ambiguous for a night owl (round 3).
                Text("\(Clock.format(range.start)) \u{2013} \(Clock.format(range.end))")
            }
            .font(.scaled(size: 12, weight: .semibold))
            .foregroundStyle(p.secondary)
            GeometryReader { geo in
                let w = geo.size.width
                let x = CGFloat(Double(range.start - trackStart) / trackLength) * w
                let width = CGFloat(Double(range.length) / trackLength) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track)
                    Capsule().fill(color)
                        .frame(width: max(8, min(width, w - max(x, 0))))
                        .offset(x: max(x, 0))
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(Clock.format(range.start)) to \(Clock.format(range.end))")
    }
}
