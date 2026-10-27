import SwiftUI
import Charts
import HealthCore

/// Clock change: the next US fall-back, what to do with the extra hour, and a
/// night-by-night plan from TimeChangePlanner. This screen only saves a
/// choice and, if she asks, bedtime reminders. It never changes her wake
/// time, bedtime or anything on the Watch.
struct TimeChangeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    private typealias Strategy = TimeChangePlanner.Strategy

    /// True once she has tapped "Use this plan". Older saves may hold the
    /// other option as a default, so until then we show "keep your usual times".
    @AppStorage("timeChange.strategyChosen") private var strategyChosen = false
    /// The option she's looking at, before saving.
    @State private var picked: Strategy? = nil
    @State private var selectedNight: String? = nil
    @State private var reminderDenied = false

    private var saved: Strategy { model.timeChangeStrategy(explicitlyChosen: strategyChosen) }
    private var strategy: Strategy { picked ?? saved }
    private var isSaved: Bool { strategyChosen && strategy == saved }
    /// She's looking at an option she hasn't saved. Reminders always follow
    /// the saved plan, so the toggle waits until she saves.
    private var hasUnsavedPick: Bool { picked != nil && picked != saved }

    /// The saved plan's reminders that are still ahead (empty once every
    /// bedtime in the plan has passed).
    private var remindersLeft: [BedtimeReminders.Reminder] {
        BedtimeReminders.timeChangeReminders(nights: model.timeChangeNights(saved),
                                             nightDate: { model.timeChangeNightDate(offset: $0) })
    }

    /// Asleep before 2:00am on the change night, so the extra hour is sleep.
    /// After that she's awake when 1:00am comes round again.
    private func asleepBeforeChange(_ ctx: ClockChangeContext) -> Bool { ctx.bedtime + 12 < 120 }

    var body: some View {
        let ctx = ClockChangeContext(model: model, strategy: strategy)
        Screen(title: "Clock change", accent: .orange) {
            SampleDataBanner()
            heroCard(ctx)
            strategyCard(ctx)
            nightsCard(ctx)
            stickCard(ctx)
            PrimaryButton(title: isSaved ? savedLabel : "Use this plan", accent: .orange, done: isSaved) {
                usePlan()
            }
            remindersCard
            Card(accent: .orange) {
                LinkRow(title: "Why this works for you", subtitle: chronotypeNote,
                        systemImage: "clock.fill", accent: .orange) { ChronotypeView() }
            }
            Text("Your phone and Watch switch to the new time on their own at 2:00am Sunday. Times on this page are by the clock you'll be using that day.")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Actions

    private func usePlan() {
        store.data.timeChangeStrategy = strategy.rawValue
        strategyChosen = true
        picked = nil
        if store.data.timeChangeReminders {
            Task { await applyReminders(on: true) }
        }
    }

    private var remindersBinding: Binding<Bool> {
        Binding(get: { store.data.timeChangeReminders },
                set: { on in
                    store.data.timeChangeReminders = on
                    reminderDenied = false
                    Task { await applyReminders(on: on) }
                })
    }

    @MainActor private func applyReminders(on: Bool) async {
        guard on else {
            await BedtimeReminders.cancelAll()
            return
        }
        // Built from the saved plan (the toggle is disabled while an unsaved
        // option is showing).
        let reminders = remindersLeft
        guard !reminders.isEmpty else {
            await BedtimeReminders.cancelAll()
            return
        }
        let ok = await BedtimeReminders.schedule(reminders)
        if !ok {
            store.data.timeChangeReminders = false
            reminderDenied = true
        }
    }

    // MARK: Hero

    private func heroCard(_ ctx: ClockChangeContext) -> some View {
        let days = model.daysUntilFallBack
        // Flips at the 2:00am change itself, not at midnight.
        let happened = model.fallBackHasHappened
        let title: String
        let heroBody: String
        switch days {
        case 0 where happened:
            title = "Clocks went back last night"
            heroBody = "At 2:00am the clock went back to 1:00am, so last night was an hour longer. Your phone and Watch already show the new time."
        case 0, 1:
            title = "Clocks go back tonight at 2am"
            heroBody = "At 2:00am the clock jumps back to 1:00am, so tonight is an hour longer. You don't have to change anything."
        default:
            title = "Clocks go back in \(days) days"
            heroBody = "At 2:00am on Sunday the clock jumps back to 1:00am, so Saturday night is an hour longer. You don't have to change anything."
        }
        return Card(accent: .orange) {
            HStack {
                SectionLabel(text: "Daylight saving ends", accent: .orange)
                Spacer()
                Label(ctx.shortDate(ctx.fallBack), systemImage: "calendar")
                    .font(.scaled(size: 13, weight: .bold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Accent.orange.tint(scheme), in: Capsule())
            }
            HStack(spacing: 0) {
                Text(title).font(.scaled(size: 24, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                InfoButton(topic: .timeChange)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("2:00")
                    .font(.scaledNumber(30))
                    .strikethrough()
                    .foregroundStyle(Palette(scheme: scheme).tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Palette(scheme: scheme).chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Image(systemName: "arrow.right")
                    .font(.scaled(size: 18, weight: .bold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                Text("1:00")
                    .font(.scaledNumber(30))
                    .foregroundStyle(Color(hex: 0x1A0E00))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Accent.orange.fill(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("am").font(.scaled(size: 15, weight: .bold)).secondaryText()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("At 2:00am the clock goes back to 1:00am")
            Text(heroBody)
                .font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Strategy

    private func strategyCard(_ ctx: ClockChangeContext) -> some View {
        let bed = Clock.format(ctx.bedtime)
        let wake = Clock.format(ctx.wake)
        let extraHour = asleepBeforeChange(ctx)
            ? "Saturday night you just get an extra hour of sleep."
            : "With a bedtime of \(bed) you'll still be up at 2:00am, so the extra hour is an hour awake (the clock reads 1:00am twice), not extra sleep."
        let keepDetail = "Same bedtime (\(bed)) and wake time (\(wake)) by the clock, every night. \(extraHour) For a few evenings you may feel sleepy about an hour earlier than usual; that fades in 3 or 4 days."
        let earlierDetail = "Your body keeps its own timing, so from Sunday you'd wake at \(Clock.format(ctx.wake - 60)) by the new clock (it'll feel like \(wake)) and go to bed at \(Clock.format(ctx.bedtime - 60)). Only worth it if you'd like to become an earlier riser."
        return Card {
            Text("What do you want to do with the extra hour?").font(.scaled(size: 17, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            ClockStrategyOption(title: "Keep your usual times", detail: keepDetail, badge: "Recommended",
                                prominent: true, selected: strategy == .keepClockTimes) {
                picked = .keepClockTimes
            }
            SectionLabel(text: "Other option")
                .padding(.top, 4)
            ClockStrategyOption(title: "Use the extra hour to wake earlier", detail: earlierDetail, badge: "Optional",
                                prominent: false, selected: strategy == .useItToWakeEarlier) {
                picked = .useItToWakeEarlier
            }
            Text(why(ctx))
                .font(.scaled(size: 14))
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Accent.orange.tint(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func why(_ ctx: ClockChangeContext) -> String {
        switch strategy {
        case .keepClockTimes:
            return "Nothing moves by the clock: bed \(Clock.format(ctx.bedtime)), up \(Clock.format(ctx.wake)), the same as now, every night. For a few evenings you may feel sleepy about an hour early; that passes once your body settles onto the new clock."
        case .useItToWakeEarlier:
            var text = "From Sunday you'd be up at \(Clock.format(ctx.wake - 60)) by the clock, an hour earlier than now, and in bed by \(Clock.format(ctx.bedtime - 60))."
            if let mel = model.energyToday.zone(.melatonin)?.range {
                text += " Your body clock doesn't change overnight, so by the new clock your melatonin window (your body's own sleep signal, not a pill) comes an hour earlier, around \(TimeRange(mel.start - 60, mel.end - 60).label). That makes the earlier bedtime easy at first."
            }
            return text
        }
    }

    // MARK: Night by night

    private func nightsCard(_ ctx: ClockChangeContext) -> some View {
        let first = ctx.nights.first.map { ctx.shortDate(ctx.date(offset: $0.dayOffset)) } ?? ""
        let last = ctx.nights.last.map { ctx.shortDate(ctx.date(offset: $0.dayOffset)) } ?? ""
        let asleep = ctx.wake - (ctx.bedtime + 12)
        let cycles = Int((Double(asleep) / Double(max(model.sleepCycleLength, 1))).rounded())
        let dots: [ClockWakeDot] = ctx.nights.map {
            ClockWakeDot(id: $0.dayOffset, label: ctx.weekday(offset: $0.dayOffset), wake: $0.wake)
        }
        let summary: String = "Wake time by the clock: " + ctx.nights.map { n in
            "\(ctx.weekday(offset: n.dayOffset)) night, up \(Clock.format(n.wake))"
        }.joined(separator: "; ")
        let selected = ctx.nights.first { ctx.weekday(offset: $0.dayOffset) == selectedNight }
            ?? ctx.nights.first { $0.dayOffset == 0 }
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Text("Night by night").font(.scaled(size: 17, weight: .bold))
                Spacer()
                Text("\(first) – \(last)").font(.scaled(size: 13)).secondaryText()
            }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Night").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Bed").frame(width: Font.scaledSize(72), alignment: .leading)
                    Text("Up next day").frame(width: Font.scaledSize(100), alignment: .leading)
                }
                .font(.scaled(size: 12, weight: .semibold))
                .secondaryText()
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
                ForEach(ctx.nights, id: \.dayOffset) { n in
                    nightRow(n, ctx)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Wake time by the clock").font(.scaled(size: 15, weight: .bold))
                Spacer()
                Text("morning after each night").font(.scaled(size: 13)).secondaryText()
            }
            .padding(.top, 4)
            if let selected {
                readout(selected, ctx)
            }
            WakeByClockChart(dots: dots, changeLabel: ctx.weekday(offset: 0),
                             selectedLabel: selectedNight, selection: $selectedNight, summary: summary)
                .frame(height: 150)
            ScrubHint()
            Text("Either way you get the same \(Clock.duration(asleep)) asleep on a normal night: \(cycles) full sleep cycles, starting about 12 minutes after bed." + (asleepBeforeChange(ctx) ? " Saturday night gets an hour on top." : " Saturday night is an hour longer, but with your bedtime that hour comes before you fall asleep."))
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Accent.purple.ink(scheme))
                    .accessibilityHidden(true)
                Text(saturdayNote(ctx)).font(.scaled(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Accent.purple.tint(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func readout(_ n: TimeChangePlanner.Night, _ ctx: ClockChangeContext) -> some View {
        let night = ctx.weekday(offset: n.dayOffset)
        let morning = ctx.weekday(offset: n.dayOffset + 1)
        let detail: String
        let diff = n.wake - ctx.wake
        if n.dayOffset == 0 {
            if strategy == .keepClockTimes {
                detail = asleepBeforeChange(ctx)
                    ? "The clocks go back at 2:00am, so you get an extra hour of sleep and still get up at your usual time."
                    : "The clocks go back at 2:00am while you're still up, so the extra hour is awake time. You still get up at your usual time."
            } else {
                detail = "The clocks go back at 2:00am. You'd get up an hour earlier by the new clock; it feels like your usual time."
            }
        } else if diff == 0 {
            detail = n.dayOffset < 0 ? "Before the change. Same as usual." : "On the new clock. Same as usual; you may feel sleepy earlier in the evening."
        } else {
            detail = "On the new clock, \(Clock.duration(abs(diff))) earlier than now. Feels like \(Clock.format(ctx.wake))."
        }
        return ChartReadout(title: "\(night) night → \(morning) morning", value: "Up \(Clock.format(n.wake))",
                            detail: "Bed \(Clock.format(n.bedtime)). \(detail)", accent: .orange)
    }

    private func nightRow(_ n: TimeChangePlanner.Night, _ ctx: ClockChangeContext) -> some View {
        let isChange = n.dayOffset == 0
        let earlier = strategy == .useItToWakeEarlier
        let date = ctx.date(offset: n.dayOffset)
        let halloween = ctx.isHalloween(date) ? "Halloween · " : ""
        let sub: String
        let wakeSub: String
        switch n.dayOffset {
        case ..<0:
            sub = "your usual"
            wakeSub = "same as usual"
        case 0:
            sub = halloween + "clocks go back at 2am"
            wakeSub = earlier ? "feels like \(Clock.format(ctx.wake))" : (asleepBeforeChange(ctx) ? "+1 hour of sleep" : "+1 hour awake")
        case 1:
            sub = "first night on the new clock"
            wakeSub = earlier ? "feels like \(Clock.format(ctx.wake))" : "same as usual"
        default:
            sub = earlier ? "an hour earlier by the clock" : "may feel sleepy earlier"
            wakeSub = earlier ? "feels like \(Clock.format(ctx.wake))" : "same as usual"
        }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ctx.shortDate(date)).font(.scaled(size: 14, weight: .bold))
                Text(sub)
                    .font(.scaled(size: 12, weight: isChange ? .bold : .regular))
                    .foregroundStyle(isChange ? Accent.orange.ink(scheme) : Palette(scheme: scheme).secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Clock.format(n.bedtime))
                .font(.scaled(size: 14, weight: .bold))
                .frame(width: Font.scaledSize(72), alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(Clock.format(n.wake)).font(.scaled(size: 14, weight: .bold))
                Text(wakeSub).font(.scaled(size: 12)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Font.scaledSize(100), alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isChange ? Accent.orange.tint(scheme) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ctx.shortDate(date)) night, \(sub). Bed \(Clock.format(n.bedtime)). Up \(Clock.format(n.wake)), \(wakeSub).")
    }

    private func saturdayNote(_ ctx: ClockChangeContext) -> String {
        let saturday = ctx.date(offset: 0)
        let lead = ctx.isHalloween(saturday) ? "Halloween is Saturday, the extra-hour night." : "Saturday is the extra-hour night."
        switch strategy {
        case .keepClockTimes:
            return "\(lead) Out late? The extra hour is on your side. Sunday morning there's no early start: get up at your usual \(Clock.format(ctx.wake)), or later if you need it."
        case .useItToWakeEarlier:
            return "\(lead) With this option Sunday starts at \(Clock.format(ctx.wake - 60)) by the new clock. If you'll be out late, the \"keep your usual times\" option is the easier one."
        }
    }

    // MARK: Make it stick

    private func stickCard(_ ctx: ClockChangeContext) -> some View {
        let earlier = strategy == .useItToWakeEarlier
        let sunday = ctx.shortDate(ctx.date(offset: 1))
        let monday = ctx.shortDate(ctx.date(offset: 2))
        let lightTip = "Get outside within 30 minutes of waking on \(sunday) and \(monday). Daylight is what tells your body clock the new time."
        let eveningTitle = earlier ? "Keep the earlier times" : "Sleepy early in the evening?"
        let eveningTip = earlier
            ? "Bed by \(Clock.format(ctx.bedtime - 60)) and up by \(Clock.format(ctx.wake - 60)) every day, weekends too. Sleeping in gives the head start back."
            : "For 3 or 4 evenings, 10pm will feel more like 11pm. Dim the lights, but try to stay up until your usual \(Clock.format(ctx.bedtime)) so your body settles onto the new clock."
        return Card {
            Text("Make it easy").font(.scaled(size: 17, weight: .bold))
            ClockStickRow(systemImage: "sun.max.fill", accent: .yellow, title: "Morning light Sun and Mon", detail: lightTip)
            ClockStickRow(systemImage: "moon.fill", accent: .purple, title: eveningTitle, detail: eveningTip)
            if let cutoff = model.caffeineCutoffShown {
                ClockStickRow(systemImage: "cup.and.saucer.fill", accent: .coral,
                              title: "Caffeine cutoff stays \(Clock.format(cutoff))",
                              detail: "Go by the new time on your phone, not by how the afternoon feels.")
            } else {
                ClockStickRow(systemImage: "cup.and.saucer.fill", accent: .coral,
                              title: "Caffeine: \(model.caffeineNoCutoffShort.lowercased())",
                              detail: "Same as any other day, by the new time on your phone.")
            }
        }
    }

    // MARK: Reminders

    private var remindersCard: some View {
        Card {
            Toggle(isOn: remindersBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remind me at bedtime").font(.scaled(size: 15, weight: .bold))
                    Text("A notification 30 minutes before bed on each night of the plan.")
                        .font(.scaled(size: 13)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Accent.orange.fill(scheme))
            .frame(minHeight: 44)
            .disabled(hasUnsavedPick)
            if hasUnsavedPick {
                Text("Tap \"Use this plan\" first. Reminders follow the plan you save.")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.data.timeChangeReminders && remindersLeft.isEmpty {
                Text("Nothing left to remind you about: every bedtime in this plan has already passed.")
                    .font(.scaled(size: 13, weight: .semibold))
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Only a reminder. Nothing changes your alarms.", systemImage: "bell")
                .font(.scaled(size: 12)).secondaryText()
            if reminderDenied {
                Text("Notifications are off for this app. You can turn them on in the Settings app under Notifications.")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.coral.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var savedLabel: String {
        switch saved {
        case .keepClockTimes: return "Plan saved: keep your usual times"
        case .useItToWakeEarlier: return "Plan saved: an hour earlier from Sunday"
        }
    }

    private var chronotypeNote: String {
        guard let c = model.chronotype else { return "See how your body clock shapes the plan." }
        let type = c.category.rawValue.lowercased()
        return model.isEveningLeaning
            ? "You're a \(type), so your body already leans late. Keeping your usual times is the gentlest change."
            : "You're a \(type). Keeping your usual times stops your mornings drifting even earlier."
    }
}

// MARK: - Plan context

/// Everything the screen derives once per render.
private struct ClockChangeContext {
    let fallBack: Date
    let bedtime: Minutes
    let wake: Minutes
    let nights: [TimeChangePlanner.Night]
    private let calendar = Calendar.current

    @MainActor
    init(model: AppModel, strategy: TimeChangePlanner.Strategy) {
        self.fallBack = model.nextFallBack
        self.bedtime = model.store.data.bedtime
        self.wake = model.timeChangeWake
        self.nights = model.timeChangeNights(strategy)
    }

    /// The calendar date of the night with this offset (0 = the Saturday night
    /// before the Sunday change).
    func date(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset - 1, to: fallBack) ?? fallBack
    }

    func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    func weekday(offset: Int) -> String {
        date(offset: offset).formatted(.dateTime.weekday(.abbreviated))
    }

    func isHalloween(_ d: Date) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: d)
        return c.month == 10 && c.day == 31
    }
}

// MARK: - Subviews

private struct ClockWakeDot: Identifiable {
    let id: Int
    let label: String
    let wake: Int
}

private struct WakeByClockChart: View {
    var dots: [ClockWakeDot]
    var changeLabel: String
    var selectedLabel: String?
    @Binding var selection: String?
    var summary: String
    @Environment(\.colorScheme) private var scheme

    private var lo: Int { (dots.map(\.wake).min() ?? 450) - 40 }
    private var hi: Int { (dots.map(\.wake).max() ?? 510) + 40 }
    private var line: Color { Accent.orange.fill(scheme) }

    var body: some View {
        Chart {
            BarMark(x: .value("Night", changeLabel), yStart: .value("Low", lo), yEnd: .value("High", hi))
                .foregroundStyle(Accent.orange.fill(scheme).opacity(0.2))
            ForEach(dots) { d in
                LineMark(x: .value("Night", d.label), y: .value("Up", d.wake))
                    .foregroundStyle(line)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            ForEach(dots) { d in
                PointMark(x: .value("Night", d.label), y: .value("Up", d.wake))
                    .foregroundStyle(line)
                    .symbolSize(d.label == selectedLabel ? 140 : 60)
                    .annotation(position: .bottom, spacing: 4) {
                        Text(Clock.format(d.wake, suffix: false))
                            .font(.scaled(size: 11, weight: .semibold))
                            .foregroundStyle(Palette(scheme: scheme).secondary)
                    }
            }
            if let selectedLabel {
                RuleMark(x: .value("Night", selectedLabel))
                    .foregroundStyle(Palette(scheme: scheme).tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: dots.map(\.label))
        .chartYScale(domain: lo...hi)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.scaled(size: 11))
            }
        }
        .chartScrub($selection)
        .accessibilityLabel(summary)
    }
}

private struct ClockStrategyOption: View {
    var title: String
    var detail: String
    var badge: String
    var prominent: Bool
    var selected: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        let badgeAccent: Accent = prominent ? .mint : .indigo
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(selected ? Accent.orange.fill(scheme) : p.tertiary, lineWidth: selected ? 6 : 2)
                        .frame(width: 20, height: 20)
                    Text(title).font(.scaled(size: prominent ? 16 : 14, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text(badge)
                        .font(.scaled(size: 12, weight: .bold))
                        .foregroundStyle(prominent ? badgeAccent.ink(scheme) : p.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(prominent ? badgeAccent.tint(scheme) : p.chip, in: Capsule())
                }
                Text(detail).font(.scaled(size: 13)).foregroundStyle(p.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, prominent ? 14 : 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? Accent.orange.tint(scheme) : p.chip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Accent.orange.fill(scheme) : p.cardBorder, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ClockStickRow: View {
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
