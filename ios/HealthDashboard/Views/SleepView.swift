import SwiftUI

struct SleepView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sleep").serifTitleFont(34).foregroundStyle(Color.ink)
            let week = model.lastWeek
            if week.isEmpty {
                Card { Note("No sleep in Apple Health yet.") }
            } else {
                AdaptiveStack(spacing: 10) {
                    Tile(label: "Average", value: hoursMinutes(mean(week.map { Double($0.asleepMinutes) })!), fill: .lavender, ink: .mainText)
                    Tile(label: "Asleep at", value: clockTime(median(week.map { Double($0.bedtime) })!), fill: .lavender, ink: .mainText)
                    Tile(label: "Regularity", value: model.regularity.map(String.init) ?? "–", fill: .mint, ink: .mintInk)
                }
                Card {
                    CardLabel("When you slept · last \(week.count) nights", color: .muted)
                    WeekChart(nights: week)
                    AdaptiveStack(spacing: 12) {
                        HStack(spacing: 6) { Circle().fill(Color.main).frame(width: 10, height: 10); Text("School nights") }
                        HStack(spacing: 6) { Circle().fill(Color.peachBar).frame(width: 10, height: 10); Text("Fri & Sat") }
                    }
                    .scaledFont(13).foregroundStyle(Color.muted)
                }
            }
            if let n = model.lastNight, n.stages != nil {
                NavigationLink { SleepStagesView() } label: {
                    LinkCard(icon: "waveform.path.ecg", title: "Last night, stage by stage", detail: "Deep, REM, core and wake-ups")
                }.buttonStyle(.plain)
            }
            if model.regularity != nil {
                Note("Regularity (0–100) measures how much your bed and wake times move from night to night. Steady times score higher and usually feel better.")
            }
            weekendCard
            NavigationLink { LateNightView() } label: {
                LinkCard(icon: "moon.zzz.fill", title: "Late-night cost", detail: "What a 2am night costs you")
            }.buttonStyle(.plain)
            AccuracyLink(metric: .sleep)
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var weekendCard: some View {
        if let w = model.weekend {
            let shift = abs(w.midpointShift)
            Card(fill: .peach) {
                CardLabel("Weekend shift", color: .peachInk)
                Text("\(hoursMinutes(Double(shift))) \(w.midpointShift >= 0 ? "later" : "earlier")").numberFont(30).foregroundStyle(Color.ink)
                Text(shift < 60 ? "Your body clock barely moves on weekends. That’s ideal."
                     : shift < 120 ? "A small weekend shift. Monday mornings may feel a little harder."
                     : "Like flying a time zone or two every weekend. That’s why Monday mornings feel early.")
                    .scaledFont(15).foregroundStyle(Color.ink)
                let rows = [("Asleep", clockTime(w.schoolNights.bedtime), clockTime(w.weekendNights.bedtime)),
                            ("Awake", clockTime(w.schoolNights.wake), clockTime(w.weekendNights.wake)),
                            ("Sleep", hoursMinutes(w.schoolNights.asleepMinutes), hoursMinutes(w.weekendNights.asleepMinutes))]
                // The three-column table when it fits; otherwise one block per row.
                ViewThatFits(in: .horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("")
                            Text("School").fontWeight(.bold).foregroundStyle(Color.muted)
                            Text("Weekend").fontWeight(.bold).foregroundStyle(Color.muted)
                        }
                        ForEach(rows, id: \.0) { row in
                            Divider().gridCellUnsizedAxes(.horizontal)
                            patternRow(row.0, row.1, row.2)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows, id: \.0) { row in
                            if row.0 != "Asleep" { Divider() }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.0).fontWeight(.bold).foregroundStyle(Color.ink)
                                Text("School \(row.1)").foregroundStyle(Color.ink)
                                Text("Weekend \(row.2)").foregroundStyle(Color.ink)
                            }
                        }
                    }
                }
                .scaledFont(14)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Note("Your typical night over the last \(w.weeks) weeks · \(w.schoolNights.nights) school nights, \(w.weekendNights.nights) weekend nights. Sleep researchers call this shift “social jetlag.”")
            }
        } else if !model.health.nights.isEmpty {
            Card(fill: .peach) {
                CardLabel("Weekend shift", color: .peachInk)
                Note("Needs at least 4 school nights and 4 weekend nights in the last 8 weeks.")
            }
        }
    }

    private func patternRow(_ label: String, _ school: String, _ weekend: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Color.ink)
            Text(school).fontWeight(.bold).foregroundStyle(Color.ink)
            Text(weekend).fontWeight(.bold).foregroundStyle(Color.ink)
        }
    }
}

/// One bar per night from bedtime to wake, on an 8pm–12pm axis.
struct SleepStagesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Last night, ", accent: "stage by stage")
            if let n = model.lastNight, let s = n.stages {
                let usual = usualStages
                Card {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(clockTime(Double(n.bedtime))); Spacer()
                            Text("\(hoursMinutes(Double(n.asleepMinutes))) asleep").fontWeight(.bold).foregroundStyle(Color.ink); Spacer()
                            Text(clockTime(Double(n.wake)))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(hoursMinutes(Double(n.asleepMinutes))) asleep").fontWeight(.bold).foregroundStyle(Color.ink)
                            Text("\(clockTime(Double(n.bedtime))) to \(clockTime(Double(n.wake)))")
                        }
                    }
                    .scaledFont(14).foregroundStyle(Color.muted)
                    StageBars(stages: s)
                }
                AdaptiveGrid(columns: 2, spacing: 10) {
                    Tile(label: "Deep", value: hoursMinutes(Double(s.deep)), caption: usual.map { "usual \(hoursMinutes(Double($0.deep)))" }, fill: Color.periwinkle, ink: .mainText)
                    Tile(label: "REM", value: hoursMinutes(Double(s.rem)), caption: usual.map { "usual \(hoursMinutes(Double($0.rem)))" }, fill: Color.lilac, ink: Color.lilacInk)
                    Tile(label: "Core", value: hoursMinutes(Double(s.core)), caption: usual.map { "usual \(hoursMinutes(Double($0.core)))" }, fill: .lavender, ink: .mainText)
                    Tile(label: "Awake", value: "\(s.awake)m", caption: "\(s.wakeUps) wake-ups", fill: .peach, ink: .peachInk)
                }
                Card(fill: .lavender) {
                    CardLabel("What it means")
                    Text("Deep sleep repairs your body; REM (dream sleep) sorts what you learned. Core is the light sleep in between. Brief wake-ups are normal; most people don’t remember them.")
                        .scaledFont(15).foregroundStyle(Color.ink)
                }
            } else {
                Card { Note("Sleep stages come from your Apple Watch when you wear it to bed.") }
            }
        }
        .detailPage()
    }

    private var usualStages: SleepStages? {
        let recent = model.health.nights.suffix(29).dropLast().compactMap(\.stages)
        guard recent.count >= 5 else { return nil }
        func m(_ f: (SleepStages) -> Int) -> Int { Int(median(recent.map { Double(f($0)) })!) }
        return SleepStages(deep: m(\.deep), rem: m(\.rem), core: m(\.core), awake: m(\.awake), wakeUps: m(\.wakeUps))
    }
}

/// Share of the night in each stage, as horizontal bars.
struct StageBars: View {
    var stages: SleepStages
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let total = Double(max(1, stages.deep + stages.rem + stages.core + stages.awake))
        VStack(spacing: 6) {
            row("Awake", stages.awake, .peachBar, total)
            row("REM", stages.rem, Color(hex: 0xB48BEA), total)
            row("Core", stages.core, Color(hex: 0x9AA6FA), total)
            row("Deep", stages.deep, .mainText, total)
        }
    }
    private func row(_ name: String, _ minutes: Int, _ color: Color, _ total: Double) -> some View {
        AdaptiveStack(spacing: 8) {
            Text(name).scaledFont(12, .bold).foregroundStyle(Color.muted).frame(width: typeSize.isAccessibilitySize ? nil : 48, alignment: .leading)
            Meter(value: Double(minutes) / total, color: color, height: 20)
            Text("\(Int((Double(minutes) / total * 100).rounded()))%").font(.caption.weight(.semibold)).foregroundStyle(Color.muted).frame(minWidth: 36, alignment: .trailing)
        }
        .accessibilityElement().accessibilityLabel("\(name) \(minutes) minutes")
    }
}

struct WeekChart: View {
    var nights: [Night]
    private let start = 2.0 * 60, span = 16.0 * 60
    @ScaledMetric(relativeTo: .caption) private var dayWidth = 30.0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 8) {
            ForEach(nights, id: \.date) { n in
                HStack(spacing: 8) {
                    Text(Day.weekdayName(n.date)).scaledFont(12).foregroundStyle(Color.muted).frame(width: dayWidth, alignment: .leading)
                    GeometryReader { geo in
                        let left = fraction(n.bedtime), right = fraction(n.wake)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.track)
                            Capsule().fill(n.isWeekend ? Color.peachBar : Color.main)
                                .frame(width: max(4, (right - left) * geo.size.width))
                                .offset(x: left * geo.size.width)
                        }
                    }
                    .frame(height: 14)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Day.weekdayName(n.date, long: true)): asleep \(clockTime(Double(n.bedtime))), awake \(clockTime(Double(n.wake)))")
            }
            HStack {
                // Every other time at the accessibility sizes, so they still fit on one line.
                ForEach(typeSize.isAccessibilitySize ? ["8pm", "4am", "12pm"] : ["8pm", "12am", "4am", "8am", "12pm"], id: \.self) { t in
                    Text(t)
                    if t != "12pm" { Spacer() }
                }
            }
            .scaledFont(12).foregroundStyle(Color.muted)
            .padding(.leading, dayWidth + 8)
            .accessibilityHidden(true)
        }
    }

    private func fraction(_ minutes: Int) -> CGFloat {
        CGFloat(min(1, max(0, (Double(minutes) - start) / span)))
    }
}
