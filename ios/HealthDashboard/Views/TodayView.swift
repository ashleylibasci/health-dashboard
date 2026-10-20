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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            greeting
            switch model.healthState {
            case .loading where model.health.nights.isEmpty:
                Card { ProgressView("Reading Apple Health…").frame(maxWidth: .infinity) }
            case .failed(let message):
                Card { Note("Couldn’t read Apple Health: \(message)") }
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
                tiles
                if let nudge = model.nudges.first(where: { !nudgeHidden($0) }) {
                    NudgeCard(nudge: nudge) { hiddenNudges[nudge.id] = model.today }
                }
                if let exam = model.upcomingExams.first, !greetingIsAbout(exam) {
                    NavigationLink { ExamsView() } label: { examBanner(exam) }.buttonStyle(.plain)
                }
                more
            }
        }
        .page()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await model.refreshHealth()
            await model.refreshCalendar(force: true)
        }
    }

    private var header: some View {
        HStack {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .scaledFont(15, .semibold).foregroundStyle(Color.muted)
            Spacer()
            Button { showSettings = true } label: {
                Text(model.profile?.initial ?? "•").scaledFont(17, .bold, design: .rounded).foregroundStyle(Color.ink).limitedTextGrowth()
                    .frame(width: 44, height: 44).background(Color.peach, in: Circle())
            }
            .accessibilityLabel("Profile and settings")
        }
        .padding(.top, 8)
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
        return (Text("Good \(part), \(model.profile?.firstName ?? "there"). ") + Text(advice).italic().foregroundColor(.mainText))
            .serifTitleFont(30).foregroundStyle(Color.ink).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A rough day: the getting-sick signals are on, or recovery is low.
    private var isOffDay: Bool { model.sick != nil || (model.recoveryToday?.score ?? 100) < 60 }

    /// The exam the greeting is talking about, so the banner doesn't repeat it.
    private var greetingExam: CalendarEvent? {
        guard !isOffDay else { return nil }
        return model.upcomingExams.first { Day.between(model.today, $0.date) <= 3 }
    }

    private func greetingIsAbout(_ exam: CalendarEvent) -> Bool { greetingExam == exam }

    private var advice: String {
        let today = model.today
        // On a rough day the cards below carry the detail; keep the greeting short.
        if isOffDay { return "Go easy today." }
        if let exam = greetingExam {
            let d = Day.between(today, exam.date)
            let when = d == 0 ? "today" : d == 1 ? "tomorrow" : Day.weekdayName(exam.date, long: true)
            return "\(exam.title) is \(when), so protect your sleep before it."
        }
        if model.weekend != nil { return "Aim to be asleep by \(clockTime(Double(model.bedtimeTarget))) tonight." }
        return "Here’s what your Watch has been noticing."
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
        NavigationLink { RecoveryView() } label: {
            VStack(alignment: .leading, spacing: 14) {
                AdaptiveStack(spacing: 8) {
                    CardLabel("Recovery")
                    Spacer(minLength: 0)
                    if let r = model.recoveryToday { Pill(text: r.label, fill: .surface, ink: .ink) }
                }
                AdaptiveStack(spacing: 16) {
                    Ring(value: model.recoveryToday?.score)
                    VStack(alignment: .leading, spacing: 8) {
                        MetricRow(label: "Resting HR", value: model.health.restingHr[model.today].map { "\(Int($0.rounded())) bpm" },
                                  change: model.recoveryToday?.restingHrChange.map { d in
                                      let n = Int(d.rounded()); return n == 0 ? "your normal" : "\(abs(n)) bpm \(n > 0 ? "above" : "below") normal"
                                  }, worse: (model.recoveryToday?.restingHrChange ?? 0) >= 3)
                        MetricRow(label: "HRV", value: model.health.hrv[model.today].map { "\(Int($0.rounded())) ms" },
                                  change: model.recoveryToday?.hrvChange.map { d in
                                      let n = Int((d * 100).rounded()); return n == 0 ? "your normal" : "\(abs(n))% \(n > 0 ? "above" : "below") normal"
                                  }, worse: (model.recoveryToday?.hrvChange ?? 0) <= -0.1)
                        MetricRow(label: "Sleep", value: model.lastNight.map { hoursMinutes(Double($0.asleepMinutes)) },
                                  change: model.recoveryToday?.sleepChange.map { d in
                                      abs(d) < 15 ? "a typical night" : "\(hoursMinutes(abs(d))) \(d > 0 ? "more" : "less") than usual"
                                  }, worse: (model.recoveryToday?.sleepChange ?? 0) <= -45)
                    }
                }
                if model.recoveryToday == nil {
                    Note("Recovery fills in once there are 7 days of heart data and a night of sleep from your Watch.")
                }
            }
            .padding(20)
            .background(Color.lavender, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
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
        AdaptiveGrid(columns: 2, spacing: 12) {
            NavigationLink { SleepView() } label: {
                SmallTile(icon: "moon.fill", label: "Sleep regularity", value: model.regularity.map(String.init) ?? "–", fill: .lavender, ink: .mainText, emptyHint: "Needs a week of nights in a row")
            }
            NavigationLink { CaffeineView() } label: {
                let mg = model.caffeineToday.reduce(0) { $0 + $1.value }
                SmallTile(icon: mg > dailyCaffeineGuide ? "exclamationmark.triangle.fill" : "cup.and.saucer.fill",
                          label: mg > dailyCaffeineGuide ? "Caffeine · over 400" : "Caffeine today", value: "\(Int(mg)) mg",
                          fill: mg > dailyCaffeineGuide ? .peach : .butter, ink: mg > dailyCaffeineGuide ? .peachInk : .butterInk)
            }
            NavigationLink { FitnessView() } label: {
                SmallTile(icon: "bolt.fill", label: "Fitness age", value: model.fitness.map { "\($0.fitnessAge)" } ?? "–", fill: .mint, ink: .mintInk, emptyHint: "Needs a 20-min outdoor walk or run")
            }
            NavigationLink { StressView() } label: {
                SmallTile(icon: "face.smiling", label: "Stress this week", value: model.stress?.weekLabel ?? "–", fill: .peach, ink: .peachInk, emptyHint: "Needs a few days of Watch wear")
            }
        }
        .buttonStyle(.plain)
    }

    private func examBanner(_ exam: CalendarEvent) -> some View {
        let d = Day.between(model.today, exam.date)
        return HStack(spacing: 12) {
            AdaptiveStack(spacing: 12) {
                Image(systemName: "calendar").scaledFont(20).foregroundStyle(Color.butterInk).limitedTextGrowth()
                    .frame(width: 40, height: 40).background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(exam.title).scaledFont(15, .bold).foregroundStyle(Color.ink)
                    Text(d == 0 ? "Today" : d == 1 ? "Tomorrow · protect tonight’s sleep" : "\(Day.weekdayName(exam.date, long: true)) · protect sleep the nights before")
                        .scaledFont(14).foregroundStyle(Color.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.butter, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

struct SmallTile: View {
    var icon: String
    var label: String
    var value: String
    var fill: Color
    var ink: Color
    /// Shown instead of the number when there isn't enough data yet.
    var emptyHint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).scaledFont(18).foregroundStyle(ink).limitedTextGrowth()
                .frame(width: 40, height: 40).background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(label).scaledFont(13, .semibold).foregroundStyle(Color.muted)
            if value == "–", let emptyHint {
                Text(emptyHint).scaledFont(13).foregroundStyle(Color.muted2).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(value).numberFont(26).foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(red: 20 / 255, green: 20 / 255, blue: 40 / 255).opacity(0.06), radius: 1, y: 1)
    }
}

/// One line of the recovery card: the number, and what it means compared with normal.
struct MetricRow: View {
    var label: String
    var value: String?
    var change: String?
    var worse = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        AdaptiveStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(label).scaledFont(15).foregroundStyle(Color.ink)
            Spacer(minLength: 0)
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
                Text(value ?? "–").scaledFont(15, .bold).foregroundStyle(Color.ink)
                if let change {
                    Text(change).scaledFont(12, worse ? .bold : .regular).foregroundStyle(worse ? Color.peachInk : Color.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
