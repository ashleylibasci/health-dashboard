import SwiftUI
import Charts
import HealthCore

/// Your body clock: your chronotype from tracked sleep, social jet lag, what
/// it means for the day and what can shift it. The method lives behind
/// "Learn how we got this number", not on the page.
struct ChronotypeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    @State private var windowSelection: Int? = nil

    var body: some View {
        Screen(title: "Your body clock", accent: .orange) {
            SampleDataBanner()
            if let c = model.chronotype, !model.chronotypeIsLearning {
                let energy = model.energyToday
                heroCard(c)
                jetlagCard(c)
                dayCard(energy)
                shiftCard(c)
                timeChangeCard
            } else {
                Card {
                    Text("Still learning your body clock").font(.scaled(size: 17, weight: .bold))
                    Text("We need school nights (with an alarm) and free nights (no alarm) tracked by your Watch. So far: \(model.workNights.count) school, \(model.freeNights.count) free. Check back after a weekend.")
                        .font(.scaled(size: 14)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Hero

    private func heroCard(_ c: Chronotype) -> some View {
        let msfsc = c.midSleepFreeCorrected
        let suffix = String(Clock.format(msfsc).suffix(2))
        return Card(accent: .orange) {
            HStack(spacing: 0) {
                SectionLabel(text: "Your body clock type", accent: .orange)
                InfoButton(topic: .bodyClock).padding(.vertical, -12)
            }
            Text(c.category.rawValue).font(.scaled(size: 28, weight: .bold))
            Text(Self.plain(c.category)).font(.scaled(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack(spacing: 4, alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(c.midSleepFreeCorrected == c.midSleepFree ? "Middle of your sleep on free days" : "Body clock time (free-day middle, minus catch-up sleep)")
                    .font(.scaled(size: 14, weight: .semibold)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                InfoButton(title: "Body clock time",
                           meaning: "The halfway point between falling asleep and waking up on days with no alarm. It's the simplest way to tell how early or late your body naturally runs. When you sleep longer on free days to catch up, that extra sleep pushes the raw middle later, so we take it out." + (c.midSleepFreeCorrected == c.midSleepFree ? "" : " Your raw free-day middle is \(Clock.format(c.midSleepFree)); without the catch-up sleep it's \(Clock.format(c.midSleepFreeCorrected))."),
                           forYou: "The later it is, the more of an evening type you are, and the harder early classes feel. Morning daylight and a steady wake time pull it earlier.")
                    .padding(.vertical, -12)
                }
                if !typeSize.isAccessibilitySize { Spacer() }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Clock.format(msfsc, suffix: false)).font(.scaledNumber(34)).keepsOnOneLine()
                    Text(suffix).font(.scaled(size: 15, weight: .bold)).foregroundStyle(Accent.orange.ink(scheme)).keepsOnOneLine()
                }
                .fixedSize()
            }
            ChronotypeSpectrum(msfsc: msfsc, category: c.category)
            Text(why(c)).font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            HowWeGotThisLink(title: "Your body clock", method: method(c))
        }
    }

    /// What each type means, in plain words.
    nonisolated static func plain(_ category: Chronotype.Category) -> String {
        switch category {
        case .veryEarly: return "Your body likes to sleep and wake much earlier than most people."
        case .moderateMorning: return "Your body leans toward earlier nights and earlier mornings."
        case .intermediate: return "Right in the middle: not an early bird, not a night owl."
        case .moderateEvening: return "Your body leans toward later nights and later mornings than most people. Very common at your age."
        case .definiteEvening: return "Your body clearly prefers late nights and late mornings. Common in your late teens and early twenties."
        case .veryLate: return "Your body runs much later than most people's, so early mornings feel especially hard."
        }
    }

    /// The method, short and plain, for the "how we got this" sheet.
    private func method(_ c: Chronotype) -> String {
        let n = model.workNights.count + model.freeNights.count
        let source = model.usingSampleData ? "Sample sleep is shown until your Watch has enough nights." : "From your last \(n) nights of sleep tracked by your Watch."
        return "\(source) We find the middle of your sleep on free nights (no alarm), when your body picks its own timing. If you sleep longer on free nights to catch up, we adjust for that, so catch-up sleep doesn't make you look later than you are. This is the standard method sleep researchers use (the Munich ChronoType Questionnaire). Your type is partly genetic and runs latest around age 20. It updates as new nights come in."
    }

    private func why(_ c: Chronotype) -> String {
        var text = ""
        let melatonin = model.energyToday.zone(.melatonin)?.range.start
        let wake = model.naturalWake
        if let melatonin, let wake {
            text = "Your body is ready for sleep from about \(Clock.format(round5(melatonin))) and, left alone, would wake around \(Clock.format(round5(wake)))."
        } else if let melatonin {
            text = "Your body is ready for sleep from about \(Clock.format(round5(melatonin)))."
        } else if let wake {
            text = "Left alone, you'd wake around \(Clock.format(round5(wake)))."
        }
        if model.isEveningLeaning {
            text += " Being an evening type isn't laziness; it's how your body is built right now."
        }
        return text
    }

    // MARK: Social jet lag

    private func jetlagCard(_ c: Chronotype) -> some View {
        let sjl = c.socialJetlag
        let over = sjl >= 60
        let badgeAccent: Accent = over ? .coral : .mint
        return Card {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Social jet lag").font(.scaled(size: 17, weight: .bold))
                InfoButton(topic: .socialJetlag).padding(.vertical, -12)
                Spacer()
                Text("goal: under 1 hour").font(.scaled(size: 13)).secondaryText()
            }
            Text("How much later you sleep on free days than on school nights. It's like flying to a different time zone every weekend and back on Monday.")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 10) {
                Text(Clock.duration(sjl)).font(.scaledNumber(34)).keepsOnOneLine()
                Text(over ? "Above goal" : "Under goal")
                    .font(.scaled(size: 13, weight: .bold))
                    .foregroundStyle(badgeAccent.ink(scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(badgeAccent.tint(scheme), in: Capsule())
            }
            .accessibilityElement(children: .combine)
            if let work = model.workNightWindow, let free = model.freeNightWindow {
                windowsReadout(work: work, free: free, c: c)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                SleepWindowsChart(work: work, free: free, selected: windowSelection, selection: $windowSelection)
                    .frame(height: 110)
                    .accessibilityLabel("School nights asleep \(work.label), free days asleep \(free.label). A \(Clock.duration(sjl)) gap in the middle of your sleep.")
                ScrubHint()
                VStack(spacing: 6) {
                    legendRow(accent: .indigo, name: "School nights", detail: "\(work.label) · middle \(Clock.format(c.midSleepWork))")
                    legendRow(accent: .orange, name: "Free days", detail: "\(free.label) · middle \(Clock.format(c.midSleepFree))" + (c.midSleepFreeCorrected == c.midSleepFree ? "" : " (raw)"))
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "airplane")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .accessibilityHidden(true)
                Text(jetlagWhy(sjl)).font(.scaled(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Accent.orange.tint(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func windowsReadout(work: TimeRange, free: TimeRange, c: Chronotype) -> some View {
        guard let raw = windowSelection else {
            return ChartReadout(title: "Middle of your sleep",
                                value: "\(Clock.duration(c.socialJetlag)) later on free days",
                                detail: "School nights \(Clock.format(c.midSleepWork)), free days \(Clock.format(c.midSleepFree))." + (c.midSleepFreeCorrected == c.midSleepFree ? "" : " Your body clock time, \(Clock.format(c.midSleepFreeCorrected)), takes out the catch-up sleep."),
                                accent: .orange)
        }
        let t = Int((Double(raw) / 5).rounded()) * 5
        func state(_ r: TimeRange) -> String {
            if r.contains(t) { return "asleep until \(Clock.format(r.end))" }
            if t < r.start { return "awake, asleep at \(Clock.format(r.start))" }
            return "up since \(Clock.format(r.end))"
        }
        let inWork = work.contains(t), inFree = free.contains(t)
        let value: String
        switch (inWork, inFree) {
        case (true, true): value = "Asleep either way"
        case (false, true): value = "Asleep only on free days"
        case (true, false): value = "Asleep only on school nights"
        case (false, false): value = "Awake either way"
        }
        return ChartReadout(title: Clock.format(t), value: value,
                            detail: "School nights: \(state(work)). Free days: \(state(free)).", accent: .orange)
    }

    private func legendRow(accent: Accent, name: String, detail: String) -> some View {
        HStack {
            Circle().fill(accent.fill(scheme)).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(name).font(.scaled(size: 14)).secondaryText()
            Spacer()
            Text(detail).font(.scaled(size: 14, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private func jetlagWhy(_ sjl: Int) -> String {
        let text = Clock.duration(sjl)
        if sjl >= 60 {
            return "Every weekend your body drifts \(text) later, then the Monday alarm pulls it back. It's like crossing \(timeZones(sjl)) and back each week, which is why Mondays feel rough."
        }
        return "Your weekends run only \(text) later than school nights, so Monday mornings stay close to your body's own timing."
    }

    private func timeZones(_ minutes: Int) -> String {
        let halves = Int((Double(minutes) / 30).rounded())
        let whole = halves / 2
        let half = halves % 2 == 1
        let names = [1: "one", 2: "two", 3: "three", 4: "four"]
        let word = names[whole] ?? "\(whole)"
        if whole == 1 && !half { return "one time zone" }
        return half ? "\(word) and a half time zones" : "\(word) time zones"
    }

    // MARK: Day

    private func dayCard(_ e: EnergyDay) -> some View {
        let peakTime = round5(e.highest.time)
        let sharpest = abs(peakTime - 720) <= 30 ? "Around noon" : "Around \(Clock.format(peakTime))"
        let peakRange = e.zone(.morningPeak).map { " · \($0.range.label)" } ?? ""
        let workout = e.zone(.secondWind)?.range.label ?? "Early evening"
        let melatonin = e.zone(.melatonin)?.range.label ?? "Late evening"
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Text("What it means for your day").font(.scaled(size: 17, weight: .bold))
                Spacer()
                Text("school days").font(.scaled(size: 13)).secondaryText()
            }
            ChronoInfoRow(systemImage: "bolt.fill", accent: .mint, label: "Sharpest focus", value: sharpest + peakRange,
                          note: "Save it for your hardest studying.", topic: .morningPeak)
            if model.hidesEffortTargets {
                ChronoInfoRow(systemImage: "sparkles", accent: .orange, label: "Second wind", value: workout,
                              note: "Your energy lifts again here. Good for group study or seeing friends.", topic: .secondWind)
            } else {
                ChronoInfoRow(systemImage: "figure.run", accent: .orange, label: "Second wind", value: workout,
                              note: "Your energy lifts again here: a good time for a workout or group study.", topic: .secondWind)
            }
            ChronoInfoRow(systemImage: "moon.fill", accent: .purple, label: "Melatonin window", value: melatonin,
                          note: "Your body's own sleep hormone has been rising for a while (it usually starts about 2 hours before you normally fall asleep). Not about melatonin pills. Falling asleep tends to come easiest now.",
                          topic: .melatonin)
            LinkRow(title: "See your energy peaks", systemImage: "chart.xyaxis.line", accent: .mint) { EnergyView() }
        }
    }

    // MARK: What can shift it

    private func shiftCard(_ c: Chronotype) -> some View {
        // After midnight this is the app day's daylight (yesterday's), not 0.
        let daylightText = model.daylightThisAppDay.map { "\($0) min today" } ?? "No reading yet today"
        let work = model.workNightWindow
        let free = model.freeNightWindow
        let wakeDetail: String
        let shiftDetail: String
        if let work, let free {
            let target = work.end + 60
            if free.end > target {
                wakeDetail = "Your wake time swings from \(Clock.format(work.end)) on school days to \(Clock.format(free.end)) on weekends. Getting up by \(Clock.format(target)) on Saturday and Sunday anchors the clock."
            } else {
                wakeDetail = "Your weekend wake-ups stay within an hour of \(Clock.format(work.end)). Keeping it that way anchors the clock."
            }
            let onset = roundUp15(work.start)
            let newGap = abs((onset + target) / 2 - (work.start + work.end) / 2)
            if c.socialJetlag > newGap + 10 {
                shiftDetail = "Asleep by \(Clock.format(onset)) and up by \(Clock.format(target)) on Fri and Sat cuts your social jetlag from \(Clock.duration(c.socialJetlag)) to about \(Clock.duration(newGap))."
            } else {
                shiftDetail = "Your weekend shift is already small. Keeping it under an hour protects Monday mornings."
            }
        } else {
            wakeDetail = "Getting up within an hour of your school-day time on weekends anchors the clock."
            shiftDetail = "Keeping weekend sleep within an hour of school nights protects Monday mornings."
        }
        let daylightDetail = "The strongest signal your clock gets. \(daylightText). Time outside before noon, day after day, moves your peak earlier."
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Text("What can shift it").font(.scaled(size: 17, weight: .bold))
                Spacer()
                Text(model.isEveningLeaning ? "earlier, a little at a time" : "a little at a time")
                    .font(.scaled(size: 13)).secondaryText()
            }
            ChronoDetailRow(systemImage: "sun.max.fill", accent: .yellow, title: "Morning daylight", detail: daylightDetail)
            ChronoDetailRow(systemImage: "alarm.fill", accent: .orange, title: "A steady wake time", detail: wakeDetail)
            ChronoDetailRow(systemImage: "calendar", accent: .purple, title: "A smaller weekend shift", detail: shiftDetail)
            LinkRow(title: "Plan your wake time", systemImage: "alarm", accent: .orange) { WakePlanView() }
        }
    }


    // MARK: Clock change

    private var timeChangeCard: some View {
        let date = model.nextFallBack.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let subtitle = model.isEveningLeaning
            ? "Good news for an evening type: for a few days after the clocks go back, an 8am start feels like 9am to your body. See the plan."
            : "For a few days after the clocks go back, you'll wake an hour earlier by the clock (6am feels like 7am). See the plan."
        return Card(accent: .orange) {
            LinkRow(title: "Clocks go back \(date)", subtitle: subtitle,
                    systemImage: "clock.arrow.circlepath", accent: .orange) { TimeChangeView() }
        }
    }

    // MARK: Helpers

    private func round5(_ m: Minutes) -> Minutes { Int((Double(m) / 5).rounded()) * 5 }
    private func roundUp15(_ m: Minutes) -> Minutes { Int((Double(m) / 15).rounded(.up)) * 15 }
}


// MARK: - Subviews

/// The very-early to very-late spectrum, 2am to 8am, with a marker. Drag
/// along it to see what each type means.
private struct ChronotypeSpectrum: View {
    var msfsc: Minutes
    var category: Chronotype.Category
    @State private var dragFraction: CGFloat? = nil
    @Environment(\.colorScheme) private var scheme

    private var colors: [Color] {
        [Accent.yellow.fill(scheme),
         scheme == .dark ? Color(hex: 0xFFC56E) : Color(hex: 0xE8A33A),
         Accent.orange.fill(scheme),
         Accent.coral.fill(scheme),
         Accent.purple.fill(scheme),
         Accent.indigo.fill(scheme)]
    }

    private var index: Int { Chronotype.Category.allCases.firstIndex(of: category) ?? 2 }

    /// 0...1 across 2am–8am.
    private var fraction: CGFloat {
        let m = msfsc > 720 ? msfsc - 1440 : msfsc
        let f = (Double(m) - 120) / 360
        return CGFloat(min(max(f, 0.02), 0.98))
    }

    private var readout: ChartReadout {
        guard let f = dragFraction else {
            return ChartReadout(title: "You", value: category.rawValue,
                                detail: "Drag along the bar to compare the types.", accent: .orange)
        }
        let mid = 120 + Int((Double(f) * 360).rounded())
        let cat = Chronotype.category(for: mid)
        let you = cat == category ? " That's you." : ""
        return ChartReadout(title: "Middle of sleep around \(Clock.format(Int((Double(mid) / 15).rounded()) * 15))",
                            value: cat.rawValue,
                            detail: ChronotypeView.plain(cat) + you, accent: .orange)
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 6) {
            readout
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            GeometryReader { geo in
                let x = geo.size.width * fraction
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 3) {
                        ForEach(0..<6) { i in
                            Capsule()
                                .fill(colors[i])
                                .opacity(i == index ? 1 : 0.45)
                                .frame(height: 12)
                        }
                    }
                    .offset(y: 24)
                    Text("You")
                        .font(.scaled(size: 12, weight: .bold))
                        .position(x: x, y: 7)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(colors[index], lineWidth: 4))
                        .position(x: x, y: 30)
                    if let f = dragFraction {
                        Rectangle()
                            .fill(p.primary.opacity(0.6))
                            .frame(width: 2, height: 30)
                            .position(x: geo.size.width * f, y: 30)
                    }
                    ForEach(1..<6) { i in
                        Text("\(i + 2)am")
                            .font(.scaled(size: 11, weight: .semibold))
                            .foregroundStyle(p.tertiary)
                            .position(x: geo.size.width * CGFloat(i) / 6, y: 56)
                    }
                }
                .contentShape(Rectangle())
                .overlay(ScrubSurface { location in
                    let w = max(geo.size.width, 1)
                    dragFraction = min(max(location.x / w, 0), 1)
                })
            }
            .frame(height: 64)
            HStack {
                Text("Very early")
                Spacer()
                Text("Very late")
            }
            .font(.scaled(size: 12, weight: .semibold))
            .foregroundStyle(p.secondary)
            ScrubHint(text: "Touch and drag along the bar")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body clock spectrum from very early to very late. Your body clock time (free-day sleep middle, minus catch-up sleep) is \(Clock.format(msfsc)), a \(category.rawValue.lowercased()).")
    }
}

/// School-night vs free-day sleep windows on one timeline.
private struct SleepWindowsChart: View {
    var work: TimeRange
    var free: TimeRange
    var selected: Int?
    @Binding var selection: Int?
    @Environment(\.colorScheme) private var scheme

    private var lo: Int { min(work.start, free.start) - 30 }
    private var hi: Int { max(work.end, free.end) + 30 }
    private var ticks: [Int] {
        let first = Int((Double(lo) / 120).rounded(.up)) * 120
        return Array(stride(from: first, through: hi, by: 120))
    }

    var body: some View {
        Chart {
            bars
            mids
            selectionMark
        }
        .chartXScale(domain: lo...hi)
        .chartYAxis(.hidden)
        .accessibilityLabel("School nights asleep \(work.label), free days asleep \(free.label).")
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(Clock.format(m)).font(.chartLabel(size: 11)).foregroundStyle(Palette(scheme: scheme).tertiary)
                    }
                }
            }
        }
        .chartScrub($selection)
    }

    @ChartContentBuilder private var bars: some ChartContent {
        BarMark(xStart: .value("Asleep", work.start), xEnd: .value("Woke", work.end), y: .value("Night", "School nights"))
            .foregroundStyle(Accent.indigo.fill(scheme))
            .cornerRadius(6)
        BarMark(xStart: .value("Asleep", free.start), xEnd: .value("Woke", free.end), y: .value("Night", "Free days"))
            .foregroundStyle(Accent.orange.fill(scheme))
            .cornerRadius(6)
    }

    @ChartContentBuilder private var mids: some ChartContent {
        RuleMark(x: .value("Mid", (work.start + work.end) / 2))
            .foregroundStyle(Accent.indigo.ink(scheme))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        RuleMark(x: .value("Mid", (free.start + free.end) / 2))
            .foregroundStyle(Accent.orange.ink(scheme))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
    }

    @ChartContentBuilder private var selectionMark: some ChartContent {
        if let selected {
            RuleMark(x: .value("Selected", selected))
                .foregroundStyle(Palette(scheme: scheme).primary)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
    }
}

private struct ChronoInfoRow: View {
    var systemImage: String
    var accent: Accent
    var label: String
    var value: String
    var note: String
    var topic: Topic
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 36, height: 36)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.scaled(size: 13)).secondaryText()
                Text(value).font(.scaled(size: 15, weight: .bold))
                Text(note).font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            InfoButton(topic: topic)
        }
    }
}

private struct ChronoDetailRow: View {
    var systemImage: String
    var accent: Accent
    var title: String
    var detail: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 36, height: 36)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(size: 15, weight: .bold))
                Text(detail).font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

