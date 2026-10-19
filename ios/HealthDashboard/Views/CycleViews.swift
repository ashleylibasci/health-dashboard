import SwiftUI

/// Picks the right cycle screen for the profile: natural, irregular, or hormonal birth control.
struct CycleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.profile?.cycle {
        case .natural?: CycleCalendarView()
        case .irregular?: IrregularCycleView()
        case .hormonal? where model.profile?.birthControl == .copperIUD: CycleCalendarView()
        case .hormonal?: PillCycleView()
        default: VStack { Note("Cycle tracking is off. Turn it on in Settings.") }.detailPage()
        }
    }
}

struct CycleCalendarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdaptiveStack(alignment: .firstTextBaseline) {
                Text(Date.now.formatted(.dateTime.month(.wide))).serifTitleFont(34).foregroundStyle(Color.ink)
                Spacer(minLength: 0)
                if let c = model.cycle { Text("Day \(c.day) · \(c.phase.rawValue)").scaledFont(15).foregroundStyle(Color.muted) }
            }
            if let c = model.cycle {
                MonthGrid(cycle: c, flow: model.health.flow)
                FlowLayout {
                    ForEach(CyclePhase.allCases, id: \.self) { p in
                        HStack(spacing: 6) { Circle().fill(p.color).frame(width: 12, height: 12); Text(p.rawValue).scaledFont(13, .bold) }
                            .padding(.horizontal, 12).padding(.vertical, 6).background(Color.surface, in: Capsule())
                    }
                }
                Card(fill: .peach) {
                    CardLabel("Next period", color: .peachInk)
                    if let next = c.nextStart {
                        Text("\(shortDay(Day.shift(next, -1))) – \(shortDay(Day.shift(next, 3)))").numberFont(28).foregroundStyle(Color.ink)
                    } else {
                        Text("Not predicted").numberFont(24).foregroundStyle(Color.ink)
                    }
                    let temps = temperatureDeviation(model.health.wristTemp)
                    if temps.count >= 7 {
                        TrendLine(values: temps.map(\.value)).frame(height: 60)
                        Note(c.ovulationDay != nil
                             ? "Wrist temperature rose after ovulation (around day \(c.ovulationDay!)). When it drops, your period is usually about a day away."
                             : "No clear temperature rise yet this cycle, so ovulation timing is estimated from your cycle length.")
                    } else {
                        Note("Wear your Watch to sleep and wrist temperature will show when ovulation happened.")
                    }
                }
                NavigationLink { PhasesView() } label: {
                    LinkCard(icon: "chart.bar.fill", title: "How your cycle affects you", detail: "Sleep, heart rate and HRV in each phase")
                }.buttonStyle(.plain)
            } else {
                Card { Note("Log your period in the Log tab (or Apple’s Health app) and the calendar fills in from there.") }
            }
            Note("Not birth control. Predictions are estimates from your own logs and temperature.")
        }
        .detailPage()
    }

    private func shortDay(_ d: String) -> String { String(Day.short(d).split(separator: ",").last!).trimmingCharacters(in: .whitespaces) }
}

/// This month's calendar, colored by cycle phase, with logged flow and the expected period.
struct MonthGrid: View {
    var cycle: CycleStatus
    var flow: [String: Int]

    var body: some View {
        let cal = Calendar.current
        let today = Day.key(.now)
        let first = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        let days = cal.range(of: .day, in: .month, for: .now)!.count
        let lead = cal.component(.weekday, from: first) - 1
        VStack(spacing: 8) {
            HStack { ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { Text($0.element).lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity) } }
                .scaledFont(12, .bold).foregroundStyle(Color.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<(lead + days), id: \.self) { i in
                    if i < lead {
                        Color.clear.frame(height: 40)
                    } else {
                        let key = Day.key(cal.date(byAdding: .day, value: i - lead, to: first)!)
                        cell(key, today: today)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder private func cell(_ key: String, today: String) -> some View {
        let day = Int(key.suffix(2))!
        let cycleDay = Day.between(cycle.lastStart, key) + 1
        let expected = cycle.nextStart.map { (0..<cycle.periodLength).contains(Day.between($0, key)) } ?? false
        let logged = (flow[key] ?? 0) > 0
        let isToday = key == today
        let phase: CyclePhase? = cycleDay >= 1 && cycleDay <= cycle.typicalLength ? cycle.phase(on: cycleDay) : nil
        Text("\(day)")
            .scaledFont(15, .bold).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 2)
            .foregroundStyle(isToday ? Color.onSolid : expected && !logged ? Color.peachInk : phase == .ovulation ? .white : Color.ink)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 14).fill(isToday ? Color.solid : logged ? Color.rose : expected ? Color.surface : phase.map { $0 == .ovulation ? Color(hex: 0x5B6BE8) : $0 == .luteal ? Color.periwinkle : $0 == .period ? Color.rose : Color.blush } ?? Color.track))
            .overlay(expected && !logged ? RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xF07A6B), style: StrokeStyle(lineWidth: 2, dash: [4, 3])) : nil)
            .accessibilityLabel("\(day)\(logged ? ", period logged" : expected ? ", expected period" : phase.map { ", \($0.rawValue)" } ?? "")")
    }
}

struct PhasesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageTitle(plain: "How your cycle ", accent: "affects you")
            let stats = phaseStats(model.health)
            if stats.isEmpty {
                Card { Note("Needs two logged periods to compare phases. It gets better with each cycle.") }
            } else {
                Text("Your own averages from recent cycles, compared with your normal.").scaledFont(15).foregroundStyle(Color.muted)
                ForEach(stats, id: \.phase) { s in
                    let here = model.cycle?.phase == s.phase
                    VStack(alignment: .leading, spacing: 10) {
                        AdaptiveStack(spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) { Circle().fill(s.phase.color).frame(width: 14, height: 14); Text(s.phase.rawValue + (here ? " · now" : "")).numberFont(22) }
                            Spacer(minLength: 0)
                            Text("Days \(s.days.lowerBound)–\(s.days.upperBound)").scaledFont(14, .semibold).foregroundStyle(Color.muted)
                        }
                        AdaptiveStack(spacing: 8) {
                            mini("Sleep", s.sleep.map { ($0 >= 0 ? "+" : "−") + "\(Int(abs($0)))m" } ?? "–")
                            mini("Resting HR", signed(s.restingHr, ""))
                            mini("HRV", signed(s.hrv, " ms"))
                        }
                        Text(note(s.phase)).scaledFont(15).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(s.phase.tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(here ? RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.mainText, lineWidth: 2) : nil)
                }
            }
            Note("Patterns from your own data, not medical advice. If something feels off, talk to a doctor.")
        }
        .detailPage()
    }

    private func mini(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).scaledFont(12).foregroundStyle(Color.muted)
            Text(value).scaledFont(18, .bold).foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func note(_ p: CyclePhase) -> String {
        switch p {
        case .period: "Many people sleep a little more. Cramps can wake you and dip recovery on days 1–2."
        case .follicular: "Often the best-recovered stretch. A good week for hard workouts."
        case .ovulation: "Wrist temperature starts to climb. This is how the app spots ovulation."
        case .luteal: "Warmer nights and lighter sleep are common. An earlier bedtime and earlier last coffee help most."
        }
    }
}

struct IrregularCycleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Your cycle, ", accent: "your way")
            if let c = model.cycle {
                Card(fill: Color.blush) {
                    CardLabel("Day \(c.day) since your last period", color: .peachInk)
                    Text("No countdown here. When cycles vary a lot, a predicted date would be wrong more often than right.").scaledFont(15).foregroundStyle(Color.ink)
                }
            }
            let ps = periods(model.health.flow)
            let lengths = Array(zip(ps, ps.dropFirst()).suffix(6))
            if !lengths.isEmpty {
                Card {
                    CardLabel("Your last \(lengths.count) cycles", color: .muted)
                    ForEach(lengths, id: \.0.start) { a, b in
                        let days = Day.between(a.start, b.start)
                        AdaptiveStack(spacing: 10) {
                            Text(Day.short(a.start).split(separator: " ").dropFirst().first.map(String.init) ?? "").scaledFont(13).foregroundStyle(Color.muted).frame(width: typeSize.isAccessibilitySize ? nil : 40, alignment: .leading)
                            HStack(spacing: 10) {
                                Meter(value: Double(days) / 50, color: days > 35 ? .peachBar : Color(hex: 0x9AA6FA), height: 14)
                                Text("\(days) days").scaledFont(13, .bold).frame(minWidth: 60, alignment: .trailing)
                            }
                        }
                    }
                    let all = lengths.map { Day.between($0.start, $1.start) }
                    Note("Range \(all.min()!)–\(all.max()!) days. That’s useful to share with a doctor.")
                }
            }
            Card(fill: .lavender) {
                CardLabel("What we can tell you")
                Text("If your wrist temperature rises and stays up, that’s the pattern that usually follows ovulation. The app points it out after it happens, never as a prediction.").scaledFont(15).foregroundStyle(Color.ink)
            }
            AdaptiveStack(spacing: 10) {
                PrimaryButton(title: "Period started") { Task { await model.logFlow(3, startsPeriod: true) } }
                if model.profile?.conditions.contains(.pcos) == true {
                    NavigationLink { PCOSView() } label: {
                        Text("About PCOS").scaledFont(16, .bold).foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 52).background(Color.surface, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
        .detailPage()
    }
}

struct PillCycleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let method = model.profile?.birthControl
        VStack(alignment: .leading, spacing: 16) {
            if let p = model.pack {
                AdaptiveStack(alignment: .firstTextBaseline) {
                    Text("Pack day \(p.day)").serifTitleFont(34).foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    Text(method?.name ?? "").scaledFont(15).foregroundStyle(Color.muted)
                }
                Card {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                        ForEach(1...28, id: \.self) { d in
                            Capsule().fill(d == p.day ? Color.mainText : d <= 21 ? (d < p.day ? Color(hex: 0x9AA6FA) : Color.periwinkle) : Color.peach)
                                .overlay(d > 21 ? Capsule().stroke(Color.peachBar, lineWidth: 2) : nil)
                                .frame(height: 32)
                        }
                    }
                    .accessibilityElement().accessibilityLabel("Day \(p.day) of 28. Days 22 to 28 are the break week.")
                    AdaptiveStack(spacing: 4) {
                        Label("Active", systemImage: "circle.fill").foregroundStyle(Color(hex: 0x9AA6FA))
                        Spacer(minLength: 0)
                        Text("Break week · bleed ~\(Day.short(p.nextBleed))").foregroundStyle(Color.muted2)
                    }.scaledFont(13)
                    if method == .combinedPill {
                        let taken = model.profile?.pillsTaken.contains(model.today) == true
                        Button { model.togglePillTaken() } label: {
                            AdaptiveStack(spacing: 2) { Text("**Today’s pill**"); Spacer(minLength: 0); Text(taken ? "Taken ✓" : "Tap when taken").fontWeight(.bold).foregroundStyle(taken ? Color.mintInk : Color.mainText) }
                                .scaledFont(15).foregroundStyle(Color.ink).padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 48)
                                .background(taken ? Color.mint : Color.lavender, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    Button("I started a new pack today") { model.startNewPack() }.scaledFont(14, .semibold).foregroundStyle(Color.mainText)
                }
            } else {
                PageTitle(plain: method?.name ?? "Birth control")
                if method?.hasPlaceboWeek == true {
                    Card {
                        Text("Track your pack: tap below on the day you start a new pack.").scaledFont(15).foregroundStyle(Color.ink)
                        PrimaryButton(title: "I started a new pack today") { model.startNewPack() }
                    }
                }
            }
            BleedCalendar(flow: model.health.flow, breakWeek: model.pack.map { p in
                let packStart = Day.shift(model.today, -(p.day - 1))
                return (21...27).map { Day.shift(packStart, $0) }
            } ?? [])
            if method?.ovulation == .stops || method?.ovulation == .sometimes {
                Card(fill: .track) {
                    CardLabel("Doesn’t apply to you*", color: .muted)
                    ForEach(["Ovulation estimate", "Fertile window", "Luteal heart-rate bump", "Phase-based predictions"], id: \.self) { o in
                        Text(o).strikethrough().scaledFont(15).foregroundStyle(Color.muted)
                    }
                    Note("*\(method?.name ?? "Your method") \(method?.ovulation == .stops ? "pauses" : "can pause") ovulation, so these natural-cycle changes don’t happen the same way.")
                }
            }
            Card(fill: .lavender) {
                CardLabel("What we still track for you")
                Bullet("Temperature, which often runs a bit higher and flatter on hormonal methods.")
                Bullet("Bleeding and spotting, whenever you log them.")
                Bullet("Mood, headaches and sleep\(method?.hasPlaceboWeek == true ? " by pack week" : "").")
            }
            if let method {
                NavigationLink { BirthControlView(method: method) } label: {
                    LinkCard(icon: "book.fill", title: "How the \(method.name.lowercased()) affects your body", detail: "What changes in your Watch data, and what to watch for")
                }.buttonStyle(.plain)
            }
        }
        .detailPage()
    }
}

struct BirthControlView: View {
    var method: BirthControl

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Pill(text: "Your method", fill: Color.periwinkle, ink: .mainText)
            PageTitle(plain: "How the ", accent: method.name.lowercased(), after: " works in your body")
            Card {
                CardLabel("Your cycle", color: .muted)
                Text(cycleText).scaledFont(15).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            }
            Card(fill: .lavender) {
                CardLabel("What changes in your Watch data")
                ForEach(dataChanges, id: \.self) { Bullet(LocalizedStringKey($0)) }
            }
            if method.ovulation == .stops {
                Card {
                    CardLabel("What the app turns off, and why", color: .muted)
                    Text("Ovulation estimates, the fertile window and phase-based predictions. Your method changes the natural temperature pattern, so those wouldn’t mean anything. Apple’s Health app does the same.")
                        .scaledFont(15).foregroundStyle(Color.ink)
                }
            }
            Card(fill: .peach) {
                CardLabel("Get care right away if", color: .peachInk)
                Text(warning).scaledFont(15).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Never change your birth control because of this app").scaledFont(15, .bold)
                Text("Talk to your doctor or nurse before starting, stopping or switching. This app is not birth control.").scaledFont(14).foregroundStyle(Color.muted2)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(hex: 0xC9CFFF), lineWidth: 2))
            Link(destination: URL(string: "https://www.nhs.uk/contraception/methods-of-contraception/")!) {
                HStack { Text("Learn more from the NHS").fontWeight(.bold); Spacer(); Image(systemName: "arrow.up.right") }
                    .scaledFont(15).foregroundStyle(Color.mainText).padding(16)
                    .background(Color.lavender, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .detailPage()
    }

    private var cycleText: String {
        switch method.ovulation {
        case .stops where method.hasPlaceboWeek:
            "The estrogen and progestin stop ovulation, so there are no natural phases (follicular, ovulation, luteal). Your month is active days and a break week. The bleed in the break week is a withdrawal bleed caused by the hormones pausing, not a true period."
        case .stops:
            "\(method.name == "Implant" ? "The implant" : "The shot") releases progestin that stops ovulation in most people. Bleeding can be irregular, light, or stop altogether, and all of those are common."
        case .sometimes:
            "The mini pill’s progestin thickens cervical mucus; it stops ovulation in some people but not all, so your cycle may stay partly natural. Bleeding can be unpredictable."
        case .mostStill:
            "A hormonal IUD works mostly inside the uterus. Most people still ovulate, so natural phases often continue, but periods usually get lighter or stop."
        case .natural:
            "A copper IUD has no hormones, so your natural cycle continues as before. Periods can be heavier or crampier, especially in the first months."
        }
    }

    private var dataChanges: [String] {
        switch method.ovulation {
        case .stops: ["**Temperature** tends to sit a little higher and stay flat, instead of rising after ovulation.", "**Heart rate and HRV** swing less across the month than in a natural cycle.", "**Sleep:** small studies saw slight changes in sleep stages on hormonal methods. Too early to say it matters."]
        case .sometimes, .mostStill: ["**Temperature** may or may not show the rise after ovulation, depending on whether you ovulate that cycle.", "**Heart rate and HRV** may still follow your cycle.", "The app shows phases only when your temperature shows them."]
        case .natural: ["Your **temperature, heart rate and HRV** follow your natural cycle, so all cycle features work as usual.", "Heavier periods can lower iron over time, which can show up as tiredness and a higher resting heart rate."]
        }
    }

    private var warning: String {
        method.hasPlaceboWeek || method == .combinedPill
            ? "Leg pain or swelling, chest pain, or sudden shortness of breath. These can be signs of a blood clot, a rare risk with estrogen. New migraines with aura: tell your doctor."
            : method == .copperIUD || method == .hormonalIUD
                ? "Severe pelvic pain, fever, or unusual discharge, especially in the first weeks after insertion. Bleeding heavy enough to soak a pad every hour."
                : "Severe headaches, heavy bleeding that soaks a pad every hour, or signs of infection where the implant or shot was placed."
    }
}

struct ConditionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageTitle(plain: "Anything we ", accent: "should know?")
            Text("Optional. Adding one changes what the app shows. Private and stays on your phone.").scaledFont(15).foregroundStyle(Color.muted)
            VStack(spacing: 0) {
                ForEach(Array(Condition.allCases.enumerated()), id: \.element) { i, c in
                    if i > 0 { Divider() }
                    let on = model.profile?.conditions.contains(c) == true
                    AdaptiveStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).scaledFont(15, .bold).foregroundStyle(Color.ink)
                            Text(c.change).scaledFont(13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 12) {
                            if c == .pcos { NavigationLink("About") { PCOSView() }.scaledFont(13, .semibold) }
                            Button(on ? "Added" : "Add") {
                                if on { model.profile?.conditions.remove(c) } else { model.profile?.conditions.insert(c) }
                            }
                            .scaledFont(13, .bold).foregroundStyle(on ? .white : Color.mainText)
                            .padding(.horizontal, 12).frame(minHeight: 32).background(on ? Color.mainText : Color.lavender, in: Capsule())
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .detailPage()
    }
}

extension Condition {
    /// What adding the condition changes in the app.
    var change: String {
        switch self {
        case .pcos: "No countdowns, wider ranges, no “late period” alerts."
        case .endometriosis: "Pain and sleep-disruption logging, cycle history for your doctor."
        case .thyroid: "Re-learns your normal heart rate after dose changes."
        case .pmdd: "Mood by cycle week and a heads-up before the luteal phase."
        case .anemia: "Links heavy flow with tiredness and heart rate."
        }
    }
}

struct PCOSView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Living with ", accent: "PCOS")
            Text("Polycystic ovary syndrome is a common hormone condition. Ovulation can happen late, irregularly, or not every cycle, so periods can be far apart or unpredictable.")
                .scaledFont(15).foregroundStyle(Color.muted2).fixedSize(horizontal: false, vertical: true)
            Card {
                CardLabel("How it can show up in your data", color: .muted)
                Bullet("Long or uneven gaps between periods.")
                Bullet("Some cycles with no clear temperature rise. Watch algorithms are mostly tested on regular cycles, so treat estimates loosely.")
            }
            Card(fill: .lavender) {
                CardLabel("What the app does differently")
                Bullet("No period countdowns and no “late period” alerts.")
                Bullet("Says “no temperature shift seen,” never “you didn’t ovulate.”")
                Bullet("Keeps a cycle-length history you can show your doctor.")
            }
            Card(fill: .peach) {
                CardLabel("Talk to a doctor if", color: .peachInk)
                Text("Your period stops for 3 months or more, bleeding is very heavy, or anything feels off. Many PCOS treatments change cycles, so update the app if yours changes.")
                    .scaledFont(15).foregroundStyle(Color.ink)
            }
            Link(destination: URL(string: "https://www.nichd.nih.gov/health/topics/pcos")!) {
                HStack { Text("PCOS basics · NIH (NICHD)").fontWeight(.bold); Spacer(); Image(systemName: "arrow.up.right") }
                    .scaledFont(15).foregroundStyle(Color.mainText).padding(16)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Note("General information, not medical advice. The app can’t diagnose PCOS or any condition.")
        }
        .detailPage()
    }
}

/// Bleeding on birth control: this month's calendar with logged bleeding and spotting, the
/// expected break-week bleed for pill/ring/patch packs, quick logging, and recent bleeds.
struct BleedCalendar: View {
    @Environment(AppModel.self) private var model
    var flow: [String: Int]
    /// Dates of this pack's break week, when a withdrawal bleed is expected.
    var breakWeek: [String]
    @State private var loggedToday: Int?

    var body: some View {
        let cal = Calendar.current
        let today = Day.key(.now)
        let first = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        let days = cal.range(of: .day, in: .month, for: .now)!.count
        let lead = cal.component(.weekday, from: first) - 1
        let expected = Set(breakWeek)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel("Bleeding · \(Date.now.formatted(.dateTime.month(.wide)))", color: .muted)
                Spacer()
            }
            HStack { ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { Text($0.element).frame(maxWidth: .infinity) } }
                .font(.caption.weight(.bold)).foregroundStyle(Color.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<(lead + days), id: \.self) { i in
                    if i < lead {
                        Color.clear.frame(height: 40)
                    } else {
                        let key = Day.key(cal.date(byAdding: .day, value: i - lead, to: first)!)
                        let level = flow[key] ?? 0
                        let isToday = key == today
                        let isExpected = expected.contains(key) && level == 0
                        Text("\(Int(key.suffix(2))!)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isToday ? Color.onSolid : isExpected ? Color.peachInk : Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 14).fill(isToday ? Color.solid : level >= 3 ? Color(hex: 0xF07A6B).opacity(0.55) : level > 0 ? Color.rose : isExpected ? Color.surface : Color.track))
                            .overlay(isExpected ? RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xF07A6B), style: StrokeStyle(lineWidth: 2, dash: [4, 3])) : nil)
                            .accessibilityLabel("\(Int(key.suffix(2))!)\(level >= 3 ? ", bleeding" : level > 0 ? ", light bleeding or spotting" : isExpected ? ", break week" : "")")
                    }
                }
            }
            HStack(spacing: 12) {
                legend(Color(hex: 0xF07A6B).opacity(0.55), "Bleeding")
                legend(Color.rose, "Light or spotting")
                if !breakWeek.isEmpty { legend(Color.surface, "Break week", dashed: true) }
            }
            .font(.caption).foregroundStyle(Color.muted)

            Text("Bleeding today?").font(.subheadline.weight(.bold)).foregroundStyle(Color.ink)
            HStack(spacing: 8) {
                ForEach(Array(zip([1, 2, 3, 4], ["Spotting", "Light", "Medium", "Heavy"])), id: \.0) { level, name in
                    Chip(text: name, selected: loggedToday == level || (loggedToday == nil && flow[today] == level), selectedFill: .rose) {
                        loggedToday = level
                        let yesterday = Day.shift(today, -1)
                        Task { await model.logFlow(level == 1 ? 2 : level, startsPeriod: (flow[yesterday] ?? 0) == 0) }
                    }
                }
            }
            let recent = Array(periods(flow).suffix(3).reversed())
            if !recent.isEmpty {
                Text("Recent bleeds").font(.subheadline.weight(.bold)).foregroundStyle(Color.ink).padding(.top, 4)
                ForEach(recent, id: \.start) { p in
                    ValueRow(label: Day.short(p.start), value: "\(p.days) day\(p.days == 1 ? "" : "s")")
                }
            }
            Note("Saved to Apple Health. On the pill, ring or patch, the break-week bleed is a withdrawal bleed, not a true period; spotting in the first months is common.")
        }
        .padding(16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func legend(_ fill: Color, _ text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(fill).frame(width: 14, height: 14)
                .overlay(dashed ? RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xF07A6B), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])) : nil)
            Text(text)
        }
    }
}
