import Charts
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Binding var showSettings: Bool
    /// Nudge id → the day "Not now" was tapped. Each stays hidden for two weeks.
    @AppStorage("hiddenNudges") private var hiddenNudgesData = Data()
    private var hiddenNudges: [String: String] {
        get { (try? JSONDecoder().decode([String: String].self, from: hiddenNudgesData)) ?? [:] }
        nonmutating set { hiddenNudgesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    private func nudgeHidden(_ n: DataNudge) -> Bool {
        hiddenNudges[n.id].map { Day.between($0, model.today) < 14 } ?? false
    }

    @Namespace private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            chips
            switch model.healthState {
            case .loading where model.health.nights.isEmpty:
                Card { ProgressView("Reading Apple Health…").frame(maxWidth: .infinity) }
            case .failed(let message):
                Card {
                    Note("Couldn’t read Apple Health: \(message)")
                    PrimaryButton(title: "Try again") { Task { await model.refreshHealth() } }
                }
            case .notConnected:
                Card(fill: .lavender) {
                    CardLabel("Apple Health isn’t connected")
                    Text("Connect it to see your sleep, recovery and everything else here.").scaledFont(15).foregroundStyle(Color.ink)
                    PrimaryButton(title: "Connect Apple Health") { Task { await model.connectHealth() } }
                }
            default:
                recoveryCard
                alerts
                cycleCard
                HStack(alignment: .firstTextBaseline) {
                    Text("This week").scaledFont(17, .bold).foregroundStyle(Color.ink).accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.top, 4)
                tiles
                if let nudge = model.nudges.first(where: { !nudgeHidden($0) }) {
                    NudgeCard(nudge: nudge) { hiddenNudges[nudge.id] = model.today }
                }
                more
            }
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy, value: model.recoveryToday?.score)
        .refreshable {
            await model.refreshHealth()
            await model.refreshCalendar(force: true)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .scaledFont(13, .semibold).foregroundStyle(Color.muted).kerning(0.3)
                Text("Good \(partOfDay), \(model.profile?.firstName ?? "there")")
                    .serifTitleFont(28).foregroundStyle(Color.ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            Button { showSettings = true } label: {
                Text(model.profile?.initial ?? "•").scaledFont(17, .bold, design: .rounded).foregroundStyle(Color.ink).limitedTextGrowth()
                    .frame(width: 44, height: 44).background(Color.peach, in: Circle())
            }
            .accessibilityLabel("Profile and settings")
        }
        .padding(.top, 8)
    }

    private var partOfDay: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
    }

    /// What's coming up, as small chips under the greeting: the next exam and tonight's bedtime.
    @ViewBuilder private var chips: some View {
        let exam = model.upcomingExams.first
        if exam != nil || model.weekend != nil {
            FlowLayout {
                if let exam {
                    NavigationLink { ExamsView().navigationTransition(.zoom(sourceID: "exams", in: zoom)) } label: {
                        Chiplet(icon: "calendar", text: "\(exam.title) · \(examWhen(exam))", fill: .butter, ink: .butterInk)
                            .matchedTransitionSource(id: "exams", in: zoom)
                    }
                    .buttonStyle(.plain)
                }
                if model.weekend != nil {
                    NavigationLink { SleepView().navigationTransition(.zoom(sourceID: "bedtime", in: zoom)) } label: {
                        Chiplet(icon: "moon.fill", text: "Bed by \(clockTime(Double(model.bedtimeTarget)))", fill: .lavender, ink: .mainText)
                            .matchedTransitionSource(id: "bedtime", in: zoom)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func examWhen(_ exam: CalendarEvent) -> String {
        let d = Day.between(model.today, exam.date)
        return d == 0 ? "Today" : d == 1 ? "Tomorrow" : d < 7 ? Day.weekdayName(exam.date, long: false) : "in \(d) days"
    }

    /// A rough day: the getting-sick signals are on, or recovery is low.
    private var isOffDay: Bool { model.sick != nil || (model.recoveryToday?.score ?? 100) < 60 }

    /// The one-line take on today, at the top of the recovery card.
    private var headline: String {
        guard let r = model.recoveryToday else { return "Still learning your normal" }
        if model.sick != nil || r.score < 60 { return "Go easy today" }
        return r.score >= 80 ? "Good to go" : "Take it steady"
    }

    @ViewBuilder private var alerts: some View {
        if model.sick != nil {
            NavigationLink { SickView() } label: {
                HStack(spacing: 12) {
                    AdaptiveStack(spacing: 12) {
                        Image(systemName: "thermometer.medium").scaledFont(20).foregroundStyle(Color.peachInk).limitedTextGrowth()
                            .frame(width: 40, height: 40).background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your body’s working harder than usual").scaledFont(15, .bold).foregroundStyle(Color.ink)
                            Text("Could be a bug coming on, or just stress. A guess, not a diagnosis. Tap to log how you feel.")
                                .scaledFont(13).foregroundStyle(Color.muted).multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").scaledFont(13, .bold).foregroundStyle(Color.muted).limitedTextGrowth()
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.peach, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        if isOffDay && !model.reasons.isEmpty {
            NavigationLink { WhyOffView() } label: {
                Label("Why do I feel off today?", systemImage: "magnifyingglass")
                    .scaledFont(16, .bold).foregroundStyle(Color.onSolid)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 52).background(Color.solid, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var recoveryCard: some View {
        let r = model.recoveryToday
        return NavigationLink { RecoveryView().navigationTransition(.zoom(sourceID: "recovery", in: zoom)) } label: {
            VStack(alignment: .leading, spacing: 16) {
                AdaptiveStack(spacing: 16) {
                    ZStack {
                        Ring(value: r?.score, size: 104, track: .lavender)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline).scaledFont(20, .bold).foregroundStyle(Color.ink)
                        Text(r.map { ((model.usualRecovery.map { "Usual is \($0). " } ?? "") + $0.reason) }
                             ?? "Recovery fills in once there are 7 days of heart data and a night of sleep from your Watch.")
                            .scaledFont(14).foregroundStyle(Color.muted2).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                AdaptiveGrid(columns: 3, spacing: 8) {
                    StatCell(label: "Resting HR", value: model.health.restingHr[model.today].map { "\(Int($0.rounded()))" }, unit: "bpm",
                             change: r?.restingHrChange.map { d in
                                 let n = Int(d.rounded()); return n == 0 ? "Your normal" : "\(n > 0 ? "+" : "−")\(abs(n)) vs normal"
                             }, worse: (r?.restingHrChange ?? 0) >= 3)
                    StatCell(label: "HRV", value: model.health.hrv[model.today].map { "\(Int($0.rounded()))" }, unit: "ms",
                             change: r?.hrvChange.map { d in
                                 let n = Int((d * 100).rounded()); return n == 0 ? "Your normal" : "\(n > 0 ? "+" : "−")\(abs(n))% vs normal"
                             }, worse: (r?.hrvChange ?? 0) <= -0.1)
                    StatCell(label: "Sleep", value: model.lastNight.map { hoursMinutes(Double($0.asleepMinutes)) }, unit: nil,
                             change: r?.sleepChange.map { d in abs(d) < 15 ? "Typical" : "\(hoursMinutes(abs(d))) \(d > 0 ? "more" : "less")" },
                             worse: (r?.sleepChange ?? 0) <= -45)
                }
            }
            .padding(18)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color(red: 20 / 255, green: 20 / 255, blue: 40 / 255).opacity(0.06), radius: 1, y: 1)
            .matchedTransitionSource(id: "recovery", in: zoom)
        }
        .buttonStyle(PressScale())
        .accessibilityHint("Opens recovery details")
    }

    @ViewBuilder private var cycleCard: some View {
        if let c = model.cycle {
            NavigationLink { CycleView() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    AdaptiveStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(c.phaseKnown ? c.phase.color : Color.lavenderStrong).frame(width: 12, height: 12)
                            Text(model.profile?.cycle == .irregular || !c.phaseKnown ? "Day \(c.day) since your last period" : "Cycle day \(c.day) · \(c.phase.rawValue)")
                                .scaledFont(15, .bold).foregroundStyle(Color.ink)
                        }
                        Spacer(minLength: 0)
                        if let late = c.daysLate {
                            Text("\(late) day\(late == 1 ? "" : "s") late").scaledFont(13, .bold).foregroundStyle(Color.peachInk)
                        } else if let next = c.nextStart {
                            let d = Day.between(model.today, next)
                            Text(d == 0 ? "Period expected today" : "Period in \(d) day\(d == 1 ? "" : "s")").scaledFont(13).foregroundStyle(Color.muted)
                        }
                    }
                    if model.profile?.cycle == .natural {
                        HStack(spacing: 2) {
                            ForEach(1...max(c.typicalLength, c.day), id: \.self) { d in
                                RoundedRectangle(cornerRadius: 3).fill(d == c.day ? Color.ink : c.phase(on: d).color)
                                    .frame(height: d == c.day ? 22 : 10)
                            }
                        }
                        .frame(height: 22)
                        .accessibilityHidden(true)
                    }
                    Text(cycleNote(c)).scaledFont(14).foregroundStyle(Color.muted).multilineTextAlignment(.leading)
                }
                .padding(16)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color(red: 20 / 255, green: 20 / 255, blue: 40 / 255).opacity(0.06), radius: 1, y: 1)
            }
            .buttonStyle(.plain)
        } else if let p = model.pack {
            NavigationLink { CycleView() } label: {
                LinkCard(icon: "pills.fill", title: "Pack day \(p.day)\(p.isBreakWeek ? " · break week" : "")",
                         detail: model.profile?.pillsTaken.contains(model.today) == true ? "Today’s pill taken ✓" : "Tap to mark today’s pill", iconFill: Color.periwinkle)
            }
            .buttonStyle(.plain)
        } else if model.profile?.cycle == .hormonal {
            NavigationLink { CycleView() } label: {
                LinkCard(icon: "pills.fill", title: model.profile?.birthControl?.name ?? "Birth control", detail: "How it affects your body and your data")
            }
            .buttonStyle(.plain)
        }
    }

    private func cycleNote(_ c: CycleStatus) -> String {
        if !c.phaseKnown { return "Longer than your usual cycle, so the app isn’t guessing a phase. Log your period when it starts." }
        return switch c.phase {
        case .luteal: "Part of today’s lower HRV and warmer nights is this phase, so recovery already allows for it."
        case .period: "You often sleep a little more now. Cramps can dip recovery on days 1–2."
        case .follicular: "Usually your best-recovered stretch. A good week for harder workouts."
        case .ovulation: "Wrist temperature starts to climb around now."
        }
    }

    private var tiles: some View {
        let week = model.lastWeek
        let mg = model.caffeineToday.reduce(0) { $0 + $1.value }
        let stressDays: [Double] = model.stressBaseline.map { base in
            let daily = dailyStress(model.health.hourlyHr, resting: base)
            return (0..<7).reversed().compactMap { daily[Day.shift(model.today, -$0)] }
        } ?? []
        return AdaptiveGrid(columns: 2, spacing: 10) {
            tile("sleep", SleepView()) {
                MetricTile(icon: "moon.fill", title: "Sleep", ink: .mainText,
                           value: model.lastNight.map { hoursMinutes(Double($0.asleepMinutes)) } ?? "–",
                           detail: model.regularity.map { "Regularity \($0)" } ?? "Needs a week of nights") {
                    Sparkline(values: week.map { Double($0.asleepMinutes) / 60 }, color: .main)
                }
            }
            tile("caffeine", CaffeineView()) {
                MetricTile(icon: mg > dailyCaffeineGuide ? "exclamationmark.triangle.fill" : "cup.and.saucer.fill",
                           title: "Caffeine", ink: mg > dailyCaffeineGuide ? .peachInk : .butterInk,
                           value: "\(Int(mg)) mg", detail: "Cutoff 2pm") {
                    ProgressBar(value: mg / dailyCaffeineGuide, color: mg > dailyCaffeineGuide ? Color(hex: 0xF08A68) : Color(hex: 0xE0A800),
                                track: .butter)
                }
            }
            tile("fitness", FitnessView()) {
                MetricTile(icon: "bolt.fill", title: "Fitness age", ink: .mintInk,
                           value: model.fitness.map { "\($0.fitnessAge)" } ?? "–",
                           detail: model.fitness.map { String(format: "VO₂ max %.1f", $0.latest) } ?? "Needs an outdoor walk") {
                    Sparkline(values: (model.fitness?.monthly.suffix(7).map(\.value)) ?? [], color: Color(hex: 0x2FA472))
                }
            }
            tile("stress", StressView()) {
                MetricTile(icon: "face.smiling", title: "Stress", ink: .peachInk,
                           value: model.stress?.weekLabel ?? "–", detail: "Last 7 days") {
                    Sparkline(values: stressDays, color: Color(hex: 0xF08A68), bars: true)
                }
            }
        }
    }

    /// A tile that zooms open into its screen.
    private func tile<Destination: View, Label: View>(_ id: String, _ destination: Destination, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink { destination.navigationTransition(.zoom(sourceID: id, in: zoom)) } label: {
            label().matchedTransitionSource(id: id, in: zoom)
        }
        .buttonStyle(PressScale())
    }

    @ViewBuilder private var more: some View {
        let prefs = model.profile?.prefs ?? Preferences()
        NavigationLink { EnergyView() } label: {
            LinkCard(icon: "battery.75percent", title: "Energy and effort", detail: "Energy left, steps, sleep debt and water", iconFill: .mint, iconInk: .mintInk)
        }.buttonStyle(.plain)
        if prefs.showCalories {
            NavigationLink { CaloriesView() } label: {
                LinkCard(icon: "flame.fill", title: "Calories burned", detail: "\(Int((model.health.activeKcal[model.today] ?? 0) + (model.health.restingKcal[model.today] ?? 0))) kcal so far today", iconFill: Color.blush, iconInk: .peachInk)
            }.buttonStyle(.plain)
        }
        if prefs.streaks {
            NavigationLink { StreaksView() } label: {
                LinkCard(icon: "star.fill", title: "Streaks and wins", detail: "\(model.streakInfo.bedtimeNights) nights in bed by \(clockTime(Double(model.bedtimeTarget)))", iconFill: .butter, iconInk: .butterInk)
            }.buttonStyle(.plain)
        }
    }
}

/// A small rounded chip with an icon, for what's coming up.
struct Chiplet: View {
    var icon: String
    var text: String
    var fill: Color
    var ink: Color
    var body: some View {
        Label(text, systemImage: icon)
            .scaledFont(13, .semibold).foregroundStyle(ink)
            .padding(.horizontal, 12).frame(minHeight: 32)
            .background(fill, in: Capsule())
    }
}

/// One number in the recovery card: label, value, and how it compares with normal.
struct StatCell: View {
    var label: String
    var value: String?
    var unit: String?
    var change: String?
    var worse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).scaledFont(12, .semibold).foregroundStyle(Color.muted)
            (Text(value ?? "–").font(.number(19)) + Text(unit.map { " \($0)" } ?? "").font(.system(size: 12, weight: .semibold)).foregroundColor(.muted))
                .foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let change {
                Text(change).scaledFont(12, .semibold).foregroundStyle(worse ? Color.peachInk : Color.muted)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Color.track, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A week-at-a-glance tile: what it is, today's number, a line of context and a tiny chart.
struct MetricTile<Chart: View>: View {
    var icon: String
    var title: String
    var ink: Color
    var value: String
    var detail: String
    @ViewBuilder var chart: Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).scaledFont(13, .semibold).foregroundStyle(ink)
            Text(value).numberFont(26).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(detail).scaledFont(12, .semibold).foregroundStyle(Color.muted).lineLimit(1).minimumScaleFactor(0.8)
            chart.frame(height: 30).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(red: 20 / 255, green: 20 / 255, blue: 40 / 255).opacity(0.06), radius: 1, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title.lowercased())")
    }
}

/// Seven days as a tiny line (or bars), today marked. Decoration: the tile says the numbers.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var bars = false

    var body: some View {
        if values.count >= 2 {
            Chart(Array(values.enumerated()), id: \.offset) { i, v in
                if bars {
                    BarMark(x: .value("Day", i), y: .value("Value", v))
                        .foregroundStyle(i == values.count - 1 ? color : color.opacity(0.4))
                        .cornerRadius(3)
                } else {
                    LineMark(x: .value("Day", i), y: .value("Value", v))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    if i == values.count - 1 {
                        PointMark(x: .value("Day", i), y: .value("Value", v)).foregroundStyle(color).symbolSize(28)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: bars))
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}

/// A thin rounded progress bar.
struct ProgressBar: View {
    var value: Double
    var color: Color
    var track: Color
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Meter(value: value, color: color, track: track, height: 8)
        }
        .accessibilityHidden(true)
    }
}

/// Cards and tiles shrink a touch while pressed, so a tap feels like it landed.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
