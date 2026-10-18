import SwiftUI

struct RecoveryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Recovery ", accent: "and why")
            if let r = model.recoveryToday {
                AdaptiveStack(spacing: 18) {
                    Ring(value: r.score, size: 104)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.label).numberFont(24).foregroundStyle(Color.ink)
                        Text((model.usualRecovery.map { r.score < $0 ? "Below your usual \($0). " : "At or above your usual \($0). " } ?? "") + r.reason)
                            .scaledFont(15).foregroundStyle(Color.muted2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.lavender, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                Card {
                    CardLabel("What went into today", color: .muted)
                    ValueRow(label: "HRV vs. your normal", value: r.hrvChange.map { "\(signed($0 * 100, ""))%" } ?? "no data")
                    ValueRow(label: "Resting HR vs. normal", value: signed(r.restingHrChange, " bpm"))
                    ValueRow(label: "Sleep vs. typical", value: r.sleepChange.map { ($0 >= 0 ? "+" : "−") + hoursMinutes(abs($0)) } ?? "no data")
                    Note("Your normal is the 4 weeks before today. HRV counts most, then resting heart rate, then sleep. Around 80 is a typical day for you.")
                }
            } else {
                Card(fill: .lavender) { Note("Recovery needs 7 days of resting heart rate or HRV and a night of sleep. It fills in over your first two weeks.") }
            }
            if !model.recovery.isEmpty {
                Card {
                    CardLabel("Last \(model.recovery.count) days", color: .muted)
                    Bars(values: model.recovery.map { Double($0.score) / 100 },
                         colors: model.recovery.enumerated().map { i, d in i == model.recovery.count - 1 ? .main : d.afterLateNight ? Color(hex: 0xFFD2BD) : Color(hex: 0xC9CFFF) })
                    Note("Peach days followed a bedtime after 2am.")
                }
            }
        }
        .detailPage()
    }
}

struct StressView: View {
    @Environment(AppModel.self) private var model
    @State private var breathing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Stress")
            if let s = model.stress {
                AdaptiveStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        CardLabel("Right now", color: .peachInk)
                        Text(s.label).numberFont(30).foregroundStyle(Color.ink)
                        if let p = s.percentile {
                            Text(p >= 0.5 ? "Higher than \(Int(p * 100))% of your \(s.partOfDay)" : "Lower than \(Int((1 - p) * 100))% of your \(s.partOfDay)")
                                .scaledFont(14).foregroundStyle(Color.muted2)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Breathe 1 min") { breathing = true }
                        .scaledFont(15, .bold).foregroundStyle(Color.onSolid)
                        .padding(.horizontal, 18).frame(minHeight: 48).background(Color.solid, in: Capsule())
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
                .background(Color.peach, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                Card {
                    CardLabel("Today, from heart rate", color: .muted)
                    if s.today.isEmpty {
                        Note("No heart rate yet today.")
                    } else {
                        Bars(values: s.today.map { $0.level / 100 }, colors: s.today.map { $0.level >= 60 ? .peachBar : $0.level >= 45 ? Color(hex: 0xFFE07A) : Color(hex: 0xC9CFFF) }, height: 100, spacing: 4)
                        HStack {
                            Text(clockOfDay(s.today.first!.hour * 60)); Spacer(); Text(clockOfDay(s.today.last!.hour * 60))
                        }.scaledFont(12).foregroundStyle(Color.muted)
                        let todays = model.events.filter { $0.date == model.today && $0.minutes != nil }
                        if !todays.isEmpty {
                            FlowLayout {
                                ForEach(Array(todays.enumerated()), id: \.offset) { _, e in
                                    Pill(text: "\(clockOfDay(e.minutes!)) · \(e.title)", fill: .lavender, ink: .mainText)
                                }
                            }
                        }
                    }
                    Note("Read from how far your heart rate runs above your resting rate. Workouts show up here too.")
                }
                if !model.stressDrivers.isEmpty {
                    Card {
                        CardLabel("What raises it · what lowers it", color: .muted)
                        ForEach(model.stressDrivers, id: \.name) { f in
                            ValueRow(label: f.name, value: "\(f.change > 0 ? "+" : "−")\(Int(abs(f.change) * 100))%", valueColor: f.change > 0 ? .peachInk : .mintInk)
                        }
                        Note("Your days with each thing, compared with your average day.")
                    }
                }
            } else {
                Card { Note("Stress needs heart rate from your Watch during the day and a few weeks of resting heart rate.") }
            }
            moodCard
        }
        .detailPage()
        .sheet(isPresented: $breathing) { BreatheView() }
    }

    private var moodCard: some View {
        let week = (0..<7).reversed().map { Day.shift(model.today, -$0) }
        let byDay = Dictionary(grouping: model.health.moods, by: \.day).mapValues { mean($0.map(\.value))! }
        return Card(fill: .lavender) {
            CardLabel("How you said you felt")
            HStack(spacing: 6) {
                ForEach(week, id: \.self) { d in
                    VStack(spacing: 6) {
                        Text(String(Day.weekdayName(d).prefix(1))).scaledFont(12).foregroundStyle(Color.muted)
                        Capsule().fill(byDay[d].map { $0 >= 0.3 ? Color.mint : $0 >= -0.2 ? Color.butter : Color.peachBar } ?? .surface).frame(height: 28)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Mood logs for the last 7 days")
            Note(byDay.isEmpty ? "Log how you feel from the Log tab or the Mindfulness app on your Watch, and it shows up here." : "From your State of Mind logs in Apple Health.")
        }
    }
}

/// A one-minute paced-breathing exercise: 4 seconds in, 6 seconds out.
struct BreatheView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded = false
    @State private var secondsLeft = 60
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Circle().fill(Color.main.opacity(0.35))
                .overlay(Circle().fill(Color.main).scaleEffect(0.55))
                .frame(width: 240, height: 240)
                .scaleEffect(expanded ? 1 : 0.6)
                .animation(.easeInOut(duration: expanded ? 4 : 6), value: expanded)
                .accessibilityHidden(true)
            Text(secondsLeft == 0 ? "Nice. That’s a minute." : expanded ? "Breathe in…" : "Breathe out…").serifTitleFont(30).foregroundStyle(Color.ink)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Text("\(secondsLeft)s").numberFont(20).foregroundStyle(Color.muted)
            Spacer()
            PrimaryButton(title: secondsLeft == 0 ? "Done" : "Stop") { dismiss() }.padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
        .background(Color.lavender)
        .onAppear { expanded = true }
        .onReceive(timer) { _ in
            guard secondsLeft > 0 else { return }
            secondsLeft -= 1
            let phase = (60 - secondsLeft) % 10
            if phase == 0 { expanded = true } else if phase == 4 { expanded = false }
        }
    }
}

struct EnergyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Energy ", accent: "and effort")
            if let r = model.recoveryToday {
                let e = energyNow(recovery: r.score, activeKcal: model.health.activeKcal[model.today] ?? 0, stressedHours: model.stress?.stressedHours ?? 0)
                Card(fill: .mint) {
                    AdaptiveStack { CardLabel("Energy left", color: .mintInk); Spacer(minLength: 0); Text(Date.now.formatted(date: .omitted, time: .shortened)).scaledFont(14).foregroundStyle(Color.muted2) }
                    HStack(spacing: 12) {
                        Meter(value: Double(e.left) / 100, color: Color(hex: 0x5CC79A), track: .surface, height: 26)
                        Text("\(e.left)%").numberFont(30).foregroundStyle(Color.ink)
                    }
                    Note("Started at \(e.startedAt)% after sleep. Activity (\(Int(e.activeKcal)) active kcal) and \(e.stressedHours) stressed hour\(e.stressedHours == 1 ? "" : "s") used the rest. \(e.left >= 60 ? "Plenty for a workout." : e.left >= 35 ? "Enough for the evening, not a hard workout." : "A slow evening and an early night would help.")")
                }
            }
            AdaptiveStack(spacing: 12) {
                Card {
                    Text("LOAD VS. YOUR NORMAL").scaledFont(12, .bold).foregroundStyle(Color.muted)
                    if let l = loadVsNormal(model.health.activeKcal), l.daysOfHistory >= 14 {
                        Text(l.ratio > 1.15 ? "Higher" : l.ratio < 0.85 ? "Lighter" : "Usual").numberFont(24).foregroundStyle(Color.ink)
                        Meter(value: min(1, l.ratio / 2))
                        Note("Today’s activity on pace vs. your last 4 weeks.")
                    } else {
                        Text("Learning you").numberFont(22).foregroundStyle(Color.ink)
                        Note("Shows up after 14 days of activity.")
                    }
                }
                Card {
                    Text("STEPS").scaledFont(12, .bold).foregroundStyle(Color.muted)
                    let steps = model.health.steps[model.today] ?? 0
                    Text(steps.formatted(.number.precision(.fractionLength(0)))).numberFont(28).foregroundStyle(Color.ink)
                    Meter(value: steps / 10_000, color: Color(hex: 0x5CC79A))
                    Note("Goal 10,000")
                }
            }
            let debt = sleepDebt(model.health.nights)
            Card {
                AdaptiveStack(alignment: .firstTextBaseline) {
                    CardLabel("Sleep debt this week", color: .muted)
                    Spacer(minLength: 0)
                    Text(hoursMinutes(Double(debt.reduce(0, +)))).numberFont(22).foregroundStyle(debt.reduce(0, +) > 60 ? Color.peachInk : Color.mintInk)
                }
                Bars(values: debt.map { Double($0) / 180 }, colors: debt.map { $0 >= 45 ? .peachBar : Color(hex: 0xC9CFFF) }, height: 60, spacing: 6)
                Note(debt.reduce(0, +) <= 30 ? "Barely any. Nice." : "Minutes short of 8 hours each night. A couple of longer nights would clear \(debt.reduce(0, +) > 180 ? "most of" : "") it.")
            }
            WaterCard()
        }
        .detailPage()
    }
}

/// Water in bottles of her own size, logged in quarters.
struct WaterCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let goal = goalBottles(model.bottleMl)
        let done = model.bottlesToday
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveStack {
                CardLabel("Water")
                Spacer(minLength: 0)
                Menu {
                    ForEach(bottleSizes, id: \.ml) { b in
                        Button(b.name) { model.profile?.bottleMl = b.ml }
                    }
                } label: {
                    Label("\(bottleName(model.bottleMl)) bottle", systemImage: "chevron.up.chevron.down")
                        .scaledFont(13, .semibold).foregroundStyle(Color.mainText)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<Int(goal.rounded(.up)), id: \.self) { i in
                    BottleShape(fill: min(1, max(0, done - Double(i))))
                        .frame(width: 26, height: 52)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(bottleCount(done)) of \(bottleCount(goal)) bottles")
            Text("\(bottleCount(done)) of \(bottleCount(goal)) bottles today").scaledFont(15, .bold).foregroundStyle(Color.ink)
            AdaptiveGrid(columns: 3, spacing: 8) {
                ForEach([(0.25, "+ ¼"), (0.5, "+ ½"), (1.0, "+ 1 bottle")], id: \.0) { amount, label in
                    Button { Task { await model.logWater(bottles: amount) } } label: {
                        Text(label).scaledFont(15, .bold).foregroundStyle(amount == 1 ? Color.onSolid : Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(amount == 1 ? Color.solid : Color.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(amount == 1 ? "a full" : amount == 0.5 ? "half a" : "a quarter") bottle")
                }
            }
            Note("Goal: about 2 liters a day, which is \(bottleCount(goal)) of your bottles.")
        }
        .padding(18)
        .background(Color.lavender, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A simple water bottle outline that fills from the bottom.
struct BottleShape: View {
    var fill: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: w * 0.3).fill(Color.surface)
                RoundedRectangle(cornerRadius: w * 0.3).fill(Color.main)
                    .frame(height: h * 0.85 * fill)
                RoundedRectangle(cornerRadius: 3).fill(Color.mainText)
                    .frame(width: w * 0.5, height: h * 0.12)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: -h * 0.04)
            }
            .clipShape(RoundedRectangle(cornerRadius: w * 0.3))
        }
    }
}

struct FitnessView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Fitness")
            if let f = model.fitness {
                AdaptiveStack(spacing: 10) {
                    Tile(label: "Fitness age", value: "\(f.fitnessAge)", caption: model.profile?.age.map { "Real age \($0)" } ?? "Add your birthday in Settings", fill: .mint, ink: .mintInk)
                    Tile(label: "VO₂ max", value: String(format: "%.1f", f.latest), caption: "Peak \(String(format: "%.0f", f.peak)) in \(String(f.peakYear))", fill: .lavender, ink: .mainText)
                }
                if f.monthly.count >= 2 {
                    Card {
                        CardLabel("VO₂ max since \(f.monthly.first!.month.prefix(4))", color: .muted)
                        TrendLine(values: f.monthly.map(\.value)).frame(height: 120)
                        Note("VO₂ max is how much oxygen your body can use during hard exercise, the best single measure of heart fitness. It comes back fast: often 3–5 points in 8 weeks of regular cardio.")
                    }
                }
                Note("Fitness age compares your VO₂ max with typical values for women at each age. An estimate from your Watch, not a lab test.")
            } else {
                Card(fill: .mint) { Note("Fitness age needs a VO₂ max reading. Your Watch records one when you do an outdoor walk, run or hike of 20 minutes or more with the Workout app.") }
            }
            if let rise = restingHrRise(model.health.restingHr) {
                Card(fill: .peach) {
                    CardLabel("Mention at your checkup", color: .peachInk)
                    Text("Your resting heart rate went from **\(Int(rise.from))** to **\(Int(rise.to))** bpm over the last six months. Often it’s fitness or stress, but it’s worth a doctor hearing it.")
                        .scaledFont(15).foregroundStyle(Color.ink)
                }
            }
            let days = briskDaysThisWeek(model.health.exerciseMinutes)
            Card {
                ValueRow(label: "Brisk walks this week", value: "\(days) of 3")
                Meter(value: Double(days) / 3, color: Color(hex: 0x5CC79A))
                Note("Days with 20+ minutes of exercise. Three a week is what moves VO₂ max.")
            }
        }
        .detailPage()
    }
}

/// A smooth line chart for a short series.
struct TrendLine: View {
    var values: [Double]
    var body: some View {
        GeometryReader { geo in
            let lo = (values.min() ?? 0) - 2, hi = (values.max() ?? 1) + 2
            let pts = values.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(1, values.count - 1)), y: geo.size.height * (1 - CGFloat((v - lo) / (hi - lo))))
            }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                }.fill(Color.lavender)
                Path { p in
                    p.move(to: pts.first ?? .zero)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }.stroke(Color.main, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct CaffeineView: View {
    @Environment(AppModel.self) private var model
    @State private var showOther = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Caffeine")
            AdaptiveStack(spacing: 10) {
                Button { Task { await model.logCaffeine(130) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cup.and.saucer.fill").scaledFont(22).foregroundStyle(Color(hex: 0xFFE07A))
                        VStack(alignment: .leading) { Text("+ Latte").scaledFont(16, .bold); Text("130 mg").scaledFont(12) }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.onSolid).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.solid, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                Button { showOther.toggle() } label: {
                    Text("+ Other drink").scaledFont(16, .bold).foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 64).background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            if showOther {
                CaffeinePicker { d in Task { await model.logCaffeine(d.mg) } }
            }
            let logs = model.caffeineToday
            Card(fill: .butter) {
                AdaptiveStack(alignment: .firstTextBaseline) {
                    Text("\(Int(logs.reduce(0) { $0 + $1.value })) mg").numberFont(28).foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    if let last = logs.last { Text("Last at \(last.date.formatted(date: .omitted, time: .shortened))").scaledFont(14, .bold).foregroundStyle(Color.butterInk) }
                }
                let atBed = caffeineLeft(model.health.caffeineLogs, at: model.tonightBedtime)
                CaffeineCurve(logs: model.health.caffeineLogs, bedtime: model.tonightBedtime).frame(height: 86)
                if let warn = caffeineLimitNote(logs.reduce(0) { $0 + $1.value }) {
                    Label(warn, systemImage: "exclamationmark.triangle.fill").scaledFont(14, .semibold).foregroundStyle(Color.peachInk)
                        .padding(12).background(Color.peach, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Note(logs.isEmpty ? "Nothing logged today." : "About \(Int(atBed.rounded())) mg left at your usual bedtime (\(model.tonightBedtime.formatted(date: .omitted, time: .shortened))). Under \(Int(bedtimeCaffeineGoal)) is the goal.")
            }
            let test = cutoffTest(model.health.caffeineLogs, nights: model.health.nights)
            Card {
                AdaptiveStack { CardLabel("Your cutoff test", color: .muted); Spacer(minLength: 0); Text("\(min(21, test.daysLogged)) of 21 days").scaledFont(14, .bold) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(0..<21, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 8).fill(i < test.daysLogged ? Color(hex: 0xFFE07A) : Color.track).frame(height: 22)
                    }
                }
                .accessibilityHidden(true)
                if !test.buckets.isEmpty {
                    Text(test.isReady ? "Hours asleep, by your last caffeine" : "Early read · hours asleep").scaledFont(15, .bold).foregroundStyle(Color.ink)
                    let maxSleep = test.buckets.map(\.asleepMinutes).max() ?? 1
                    ForEach(test.buckets, id: \.label) { b in
                        AdaptiveStack(spacing: 10) {
                            Text(b.label).scaledFont(13).frame(width: typeSize.isAccessibilitySize ? nil : 120, alignment: .leading)
                            HStack(spacing: 10) {
                                Meter(value: b.asleepMinutes / maxSleep, color: b.label == "After 3pm" ? .peachBar : .main)
                                Text(hoursMinutes(b.asleepMinutes)).scaledFont(13, .bold).frame(minWidth: 56, alignment: .trailing)
                            }
                        }
                    }
                }
                Note(test.isReady ? "Based on \(test.daysLogged) days of logs." : "\(21 - test.daysLogged) more days of logs for a real answer.")
            }
        }
        .detailPage()
    }
}

/// Caffeine in your body from 6am to 2am, with a line at bedtime.
struct CaffeineCurve: View {
    var logs: [Reading]
    var bedtime: Date
    var body: some View {
        GeometryReader { geo in
            let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(6 * 3600)
            let hours = 20.0
            let values = stride(from: 0.0, through: hours, by: 0.25).map { caffeineLeft(logs, at: start.addingTimeInterval($0 * 3600)) }
            let top = max(150, values.max() ?? 0)
            ZStack(alignment: .topLeading) {
                Path { p in
                    for (i, v) in values.enumerated() {
                        let pt = CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(values.count - 1), y: geo.size.height * (1 - CGFloat(v / top)))
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }.stroke(Color(hex: 0xC99A00), lineWidth: 3)
                let bx = geo.size.width * CGFloat(bedtime.timeIntervalSince(start) / 3600 / hours)
                Path { p in p.move(to: CGPoint(x: bx, y: 0)); p.addLine(to: CGPoint(x: bx, y: geo.size.height)) }
                    .stroke(Color.mainText, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                Text("bedtime").scaledFont(12).foregroundStyle(Color.mainText).limitedTextGrowth().offset(x: max(0, bx - 56), y: 0)
            }
        }
        .accessibilityHidden(true)
    }
}

struct DrinksView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Drinks ", accent: "and your body")
            Text("No judgment, just what your own data shows the morning after.").scaledFont(15).foregroundStyle(Color.muted)
            AdaptiveGrid(columns: 5, spacing: 8) {
                ForEach(Array(zip(alcoholDrinks, [Color.lilac, .butter, .mint, .peach, .lavender])), id: \.0) { name, fill in
                    Button { Task { await model.logDrink() } } label: {
                        Text(name).scaledFont(13, .bold).foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 64).background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log a \(name.lowercased())")
                }
            }
            if let e = drinkEffect(model.health, recovery: model.recoveryByDate) {
                Card {
                    CardLabel("After 3+ drinks · \(e.nights) nights", color: .muted)
                    AdaptiveGrid(columns: 2, spacing: 10) {
                        Tile(label: "Resting HR", value: signed(e.restingHr, " bpm"), fill: .peach, ink: .peachInk)
                        Tile(label: "HRV", value: signed(e.hrv, " ms"), fill: .peach, ink: .peachInk)
                        Tile(label: "REM sleep", value: signed(e.remMinutes, " min"), fill: .lavender, ink: .mainText)
                        Tile(label: "Recovery", value: signed(e.recovery, ""), fill: .lavender, ink: .mainText)
                    }
                    Note("Compared with nights you didn’t drink. Alcohol usually lets you fall asleep fine, but your heart works harder all night and dream (REM) sleep gets cut.")
                }
                Card {
                    CardLabel("How long it takes to bounce back", color: .muted)
                    Bars(values: e.bounceBack.map { $0 * 0.85 }, colors: e.bounceBack.map { $0 < 0.8 ? .peachBar : $0 < 0.95 ? Color(hex: 0xFFD2BD) : Color(hex: 0xC9CFFF) }, height: 70, spacing: 8)
                    HStack { ForEach(["Before", "Next day", "Day 2", "Day 3"], id: \.self) { Text($0).lineLimit(2).minimumScaleFactor(0.5).multilineTextAlignment(.center).frame(maxWidth: .infinity) } }
                        .scaledFont(12).foregroundStyle(Color.muted)
                }
            } else {
                Card { Note("Needs at least 2 nights with 3+ drinks logged, and some nights without, to compare. Log drinks here or in the Log tab.") }
            }
            Card(fill: .lavender) {
                CardLabel("What helps most people")
                Bullet("Last drink 3+ hours before bed.")
                Bullet("A glass of water between drinks.")
            }
        }
        .detailPage()
    }
}

struct CaloriesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Calories ", accent: "burned")
            let rest = model.health.restingKcal[model.today] ?? 0, active = model.health.activeKcal[model.today] ?? 0
            Card(fill: Color.blush) {
                AdaptiveStack(alignment: .firstTextBaseline) {
                    Text(Int(rest + active).formatted()).numberFont(40).foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    Text("kcal so far today").scaledFont(14).foregroundStyle(Color.muted2)
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(hex: 0xFFD2BD)).frame(width: geo.size.width * CGFloat(rest / max(1, rest + active)))
                        Rectangle().fill(Color(hex: 0xF07A6B))
                    }
                }
                .frame(height: 16).clipShape(Capsule())
                AdaptiveStack { Text("Resting \(Int(rest).formatted())"); Spacer(minLength: 0); Text("Active \(Int(active).formatted())") }.scaledFont(14).foregroundStyle(Color.ink)
            }
            let week = (0..<7).reversed().map { model.health.activeKcal[Day.shift(model.today, -$0)] ?? 0 }
            Card {
                CardLabel("Active calories · last 7 days", color: .muted)
                Bars(values: week.map { $0 / max(1, week.max() ?? 1) }, colors: week.indices.map { $0 == 6 ? Color(hex: 0xF07A6B) : Color(hex: 0xFFD2BD) }, height: 90, spacing: 8)
            }
            if model.cycle != nil {
                Card(fill: .lavender) {
                    CardLabel("Your cycle and energy use")
                    Text("Resting burn often runs 60–100 kcal higher in the luteal phase. Feeling hungrier that week is normal.").scaledFont(15).foregroundStyle(Color.ink)
                }
            }
            Note("Apple Watch estimates calories from heart rate and movement. Treat these as estimates. No targets and no food diary, on purpose; turn this screen off anytime in Settings.")
        }
        .detailPage()
    }
}

/// Lays chips out in rows, wrapping as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = fitted(s, width)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = fitted(s, bounds.width)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    /// A chip's natural size, or wrapped to the row's width when it's wider (large text sizes).
    private func fitted(_ s: LayoutSubview, _ width: CGFloat) -> CGSize {
        let size = s.sizeThatFits(.unspecified)
        return size.width <= width ? size : s.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
}
