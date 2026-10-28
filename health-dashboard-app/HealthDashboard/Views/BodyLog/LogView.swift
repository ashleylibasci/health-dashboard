import SwiftUI
import HealthCore

/// The Log tab: everything you log yourself, in one place. Caffeine (at the
/// time you choose), water, drinks, stress, period and symptoms, and the
/// morning check-in. Each section links to its full screen.
struct LogView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var caffeineTime: LogTime = .now
    @State private var lastCaffeine: String?
    @State private var lastWater: String?
    @State private var lastAlcohol: String?
    @State private var logCount = 0

    var body: some View {
        Screen(accent: .indigo) {
            BodyLogTabHeader("Log today")
            SampleDataBanner(forLog: true)
            caffeineSection
            waterSection
            if store.data.drinksTracking { alcoholSection }
            stressSection
            if store.data.cycleSetup != .notTracking { cycleSection }
            checkInSection
        }
        .sensoryFeedback(.success, trigger: logCount)
    }

    // MARK: Caffeine

    private var caffeineSection: some View {
        let p = Palette(scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 0) {
                SectionLabel(text: "Caffeine", accent: .yellow)
                Spacer()
                Text("\(model.caffeineMgToday) mg today \u{00B7} " + (model.caffeineCutoffShown.map { "cutoff \(BodyLogStyle.shortTime($0))" } ?? "one small drink early"))
                    .font(.scaled(size: 13, weight: .semibold))
                    .secondaryText()
                InfoButton(topic: .caffeineCutoff).padding(.vertical, -10)
            }
            VStack(spacing: 0) {
                LogTimeSelector(time: $caffeineTime, accent: .yellow, title: "When did you have it?")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                Divider().overlay(p.cardBorder)
                ForEach(store.data.savedDrinks) { drink in
                    drinkButton(drink)
                    Divider().overlay(p.cardBorder)
                }
                NavigationLink { CustomDrinkView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.scaled(size: 15, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Accent.indigo.tint(scheme), in: Circle())
                            .accessibilityHidden(true)
                        Text("New drink").font(.scaled(size: 15, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Accent.yellow.tint(scheme), in: shape)
            .overlay(shape.strokeBorder(Accent.yellow.fill(scheme).opacity(0.18)))

            if let lastCaffeine { confirmation(lastCaffeine) }
            if model.caffeineCutoffBeforeWake {
                Text(model.caffeineEarlyOnlyText)
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card {
                LinkRow(title: "Caffeine today", subtitle: caffeineSubtitle,
                        systemImage: "cup.and.saucer.fill", accent: .yellow) {
                    CaffeineView()
                }
            }
        }
    }

    private var caffeineSubtitle: String {
        let count = model.todaysDrinks.count
        let drinks = count == 0 ? "Nothing logged yet" : "\(count) drink\(count == 1 ? "" : "s") \u{00B7} tap to edit times"
        return "\(drinks) \u{00B7} ~\(model.caffeineAtBedtime) mg left at bedtime"
    }

    private func drinkButton(_ drink: Drink) -> some View {
        Button {
            model.log(drink, at: caffeineTime.date)
            let when = store.data.drinkLog.last?.date ?? .now
            lastCaffeine = LogFormat.loggedLine(drink.name, at: when) + (AppDay.contains(when) ? " Change it in Caffeine today." : "")
            caffeineTime = .now
            logCount += 1
        } label: {
            HStack(spacing: 12) {
                Image(systemName: BodyLogStyle.symbol(for: drink.icon))
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(BodyLogStyle.accent(for: drink.icon).ink(scheme))
                    .frame(width: 36, height: 36)
                    .background(BodyLogStyle.accent(for: drink.icon).fill(scheme).opacity(0.22), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(drink.name)
                        .font(.scaled(size: 15, weight: .bold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("\(drink.caffeineMg) mg").font(.scaled(size: 13, weight: .semibold)).secondaryText()
                        if drink.isCustom { CustomDrinkBadge(accent: .purple) }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.scaled(size: 14, weight: .bold))
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .frame(width: 32, height: 32)
                    .background(Accent.yellow.fill(scheme).opacity(0.24), in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(drink.name), \(drink.caffeineMg) mg, \(caffeineTime.phrase)")
    }

    // MARK: Water

    private var bottleCount: Int { max(1, min(Int(model.waterGoalBottles.rounded(.up)), 8)) }

    private var waterText: String {
        "\(LogFormat.bottles(model.waterBottlesToday)) of \(LogFormat.bottlesPhrase(model.waterGoalBottles))"
    }

    private func addWater(_ bottles: Double) {
        model.addWater(bottles: bottles)
        lastWater = "Added \(LogFormat.oz(store.data.bottleSizeML * bottles)) at \(Clock.format(model.now))."
        logCount += 1
    }

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Water", accent: .blue)
                Spacer()
                Text(waterText).font(.scaled(size: 13, weight: .semibold)).secondaryText()
            }
            Card(accent: .blue) {
                HStack(spacing: 8) {
                    ForEach(0..<bottleCount, id: \.self) { i in
                        LogBottle(fill: min(max(model.waterBottlesToday - Double(i), 0), 1))
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(LogFormat.oz(model.waterTodayML)).font(.scaledNumber(20))
                        Text("of \(LogFormat.oz(store.data.waterGoalML))").font(.scaled(size: 12, weight: .semibold)).secondaryText()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Water, \(waterText), \(LogFormat.oz(model.waterTodayML))")
                HStack(spacing: 10) {
                    waterButton("1 bottle", bottles: 1)
                    waterButton("\u{00BD} bottle", bottles: 0.5)
                }
                if let lastWater { confirmation(lastWater) }
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                LinkRow(title: "Water", subtitle: "Bottle \(LogFormat.oz(store.data.bottleSizeML)) \u{00B7} change times, sizes and goal",
                        systemImage: "drop.fill", accent: .blue) {
                    WaterView()
                }
            }
        }
    }

    private func waterButton(_ title: String, bottles: Double) -> some View {
        Button { addWater(bottles) } label: {
            Label(title, systemImage: "plus")
                .font(.scaled(size: 14, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Accent.blue.ink(scheme))
                .background(Accent.blue.fill(scheme).opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Accent.blue.fill(scheme).opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(title) of water, \(LogFormat.oz(store.data.bottleSizeML * bottles)), now")
    }

    // MARK: Drinks (alcohol)

    private static let quickKinds = ["Wine", "Beer", "Seltzer", "Cocktail", "Shot"]

    private var alcoholToday: Int {
        AppData.today(store.data.alcoholLog, date: \.date).map(\.count).reduce(0, +)
    }

    private var alcoholSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Drinks", accent: .purple)
                Spacer()
                Text(alcoholToday == 0 ? "None today" : "\(alcoholToday) drink\(alcoholToday == 1 ? "" : "s") today")
                    .font(.scaled(size: 13, weight: .semibold)).secondaryText()
            }
            Card(accent: .purple) {
                Text("Tap to log one drink now. Change the time or number on the Drinks screen.")
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.quickKinds, id: \.self) { kind in
                            Button {
                                store.data.alcoholLog.append(AppData.AlcoholEntry(date: .now, kind: kind, count: 1))
                                lastAlcohol = "Logged \(DrinksView.phrase(count: 1, kind: kind)) at \(Clock.format(model.now))."
                                logCount += 1
                            } label: {
                                Label(kind, systemImage: "plus")
                                    .font(.scaled(size: 14, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .foregroundStyle(Accent.purple.ink(scheme))
                                    .background(Accent.purple.fill(scheme).opacity(0.18), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Accent.purple.fill(scheme).opacity(0.3)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Log one \(kind), now")
                        }
                    }
                }
                if let lastAlcohol { confirmation(lastAlcohol) }
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                LinkRow(title: "Drinks and your body", subtitle: "What drinks do to your sleep \u{00B7} edit entries",
                        systemImage: "wineglass.fill", accent: .purple) {
                    DrinksView()
                }
            }
        }
    }

    // MARK: Stress

    private var stressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Stress", accent: .coral)
            Card {
                HStack(spacing: 0) {
                    Text("How stressed do you feel?").font(.scaled(size: 15, weight: .bold))
                    InfoButton(title: "How stressed do you feel?",
                               meaning: "A quick 1 to 5 rating of how stressed you feel right now. 1 is very calm, 5 is very stressed.",
                               forYou: "The Stress screen shows it next to what your heart rate says, so you can see whether the two agree. Log again any time; the latest one counts for today.")
                        .padding(.vertical, -12)
                }
                Text("1 very calm \u{00B7} 5 very stressed").font(.scaled(size: 13)).secondaryText()
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        stressButton(level)
                    }
                }
                if let logged = model.stressLoggedToday {
                    Text("Today: \(logged) \u{00B7} \(Self.stressWord(logged)). Tap again to update.")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(Accent.coral.ink(scheme))
                }
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                LinkRow(title: "Your stress today", subtitle: "What your heart rate shows, hour by hour",
                        systemImage: "waveform.path.ecg", accent: .coral) {
                    StressView()
                }
            }
        }
    }

    static func stressWord(_ level: Int) -> String {
        switch level {
        case 1: return "very calm"
        case 2: return "calm"
        case 3: return "a bit stressed"
        case 4: return "stressed"
        default: return "very stressed"
        }
    }

    private func stressButton(_ level: Int) -> some View {
        let on = model.stressLoggedToday == level
        return Button {
            store.data.moodLog.append(AppData.MoodEntry(date: .now, stress: level))
            logCount += 1
        } label: {
            Text("\(level)")
                .font(.scaledNumber(18))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(on ? Color(hex: 0x1A0E00) : Palette(scheme: scheme).primary)
                .background(on ? Accent.coral.fill(scheme) : Palette(scheme: scheme).chip,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(on ? Accent.coral.fill(scheme) : Palette(scheme: scheme).cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stress \(level), \(Self.stressWord(level))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Cycle

    private var cycleSubtitle: String {
        switch model.cycleDisplay {
        case let .phases(day, _, phase):
            return "Day \(day) \u{00B7} \(BodyLogStyle.phaseName(phase, birthControl: store.birthControl)) \u{00B7} log flow and symptoms"
        case let .pack(day, activeDays, packLength):
            if activeDays < packLength && day > activeDays { return "Break week \u{00B7} log your bleed and symptoms" }
            return "Pack day \(day) \u{00B7} log any bleeding or symptoms"
        case let .suppressed(method):
            return "\(method.rawValue) \u{00B7} log any bleeding or symptoms"
        case let .overdue(day, typical):
            return "Day \(day) \u{00B7} longer than your usual ~\(typical) days \u{00B7} log flow and symptoms"
        case .irregular:
            if let days = model.daysSinceLastPeriodStart {
                return "\(days) day\(days == 1 ? "" : "s") since your last period started \u{00B7} log flow and symptoms"
            }
            return "Log flow and symptoms"
        case .notTracking:
            return "Log flow and symptoms"
        }
    }

    private var cycleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Cycle", accent: .pink)
            Card {
                LinkRow(title: "Period & symptoms", subtitle: cycleSubtitle,
                        systemImage: "drop.fill", accent: .pink) {
                    CycleLogView()
                }
            }
        }
    }

    // MARK: Check-in

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "How you feel", accent: .mint)
            Card {
                LinkRow(title: "Morning check-in", subtitle: checkInSubtitle,
                        systemImage: "sun.max.fill", accent: .mint) {
                    CheckInView()
                }
            }
        }
    }

    private var checkInSubtitle: String {
        if let today = store.checkIn(on: .now) { return "Done today \u{00B7} \(today.awake) of 5 awake" }
        if !model.canCheckInNow { return "Check in after you wake up" }
        return "How awake do you feel? Takes 10 seconds"
    }

    private func confirmation(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.scaled(size: 13, weight: .semibold))
            .foregroundStyle(Accent.mint.ink(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Shared by the Log, Caffeine, Water and Drinks screens

/// When something was had: a preset ("now", "30 min ago"…) or a picked time.
enum LogTime: Hashable {
    /// Minutes before now; 0 is now. Resolved when logging, so "Now" is
    /// the moment she taps, not when the screen opened.
    case ago(Int)
    case exact(Date)

    static let now = LogTime.ago(0)
    static let presets = [0, 30, 60, 120]

    static func presetLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "Now" }
        if minutes < 60 { return "\(minutes) min ago" }
        return "\(minutes / 60) hr ago"
    }

    var date: Date {
        switch self {
        case let .ago(minutes): return Date.now.addingTimeInterval(-Double(minutes) * 60)
        case let .exact(date): return date
        }
    }

    /// "now" or "at 9:10am".
    var phrase: String {
        if self == .now { return "now" }
        return "at \(Clock.format(Clock.minutesOfDay(date)))"
    }

    /// A picked clock time later than now means the evening before (picking
    /// 11:30pm just after midnight); anything else still ahead becomes now.
    static func past(_ date: Date) -> Date { AppDay.pastTime(date) }
}

/// "Now · 30 min ago · 1 hr ago · 2 hr ago" chips plus a time picker for
/// anything else.
struct LogTimeSelector: View {
    @Binding var time: LogTime
    var accent: Accent = .yellow
    var title = "When?"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(.scaled(size: 13, weight: .bold)).secondaryText()
                Spacer(minLength: 4)
                Text("Other").font(.scaled(size: 13)).secondaryText().accessibilityHidden(true)
                DatePicker("Pick another time", selection: exactTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(accent.ink(scheme))
                    .accessibilityLabel("Pick another time")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LogTime.presets, id: \.self) { minutes in
                        chip(minutes)
                    }
                }
            }
        }
    }

    private var exactTime: Binding<Date> {
        Binding(get: { time.date }, set: { time = .exact(LogTime.past($0)) })
    }

    private func chip(_ minutes: Int) -> some View {
        let p = Palette(scheme: scheme)
        let on = time == .ago(minutes)
        return Button { time = .ago(minutes) } label: {
            Text(LogTime.presetLabel(minutes))
                .font(.scaled(size: 14, weight: .bold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(on ? Color(hex: 0x1A0E00) : p.primary)
                .background(on ? accent.fill(scheme) : p.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? accent.fill(scheme) : p.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A list of today's entries that you can tap to edit and swipe to delete.
/// It sits inside the screen's scroll view, so it has a fixed height and
/// doesn't scroll itself.
struct LogEntryList<Item: Identifiable, Row: View>: View {
    var items: [Item]
    var rowHeight: CGFloat = 64
    var onTap: (Item) -> Void
    var onDelete: (Item) -> Void
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        List {
            ForEach(items) { item in
                Button { onTap(item) } label: {
                    row(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: Font.scaledSize(rowHeight))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                // No full swipe: a short swipe shows Delete, so nothing goes by accident.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { onDelete(item) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .accessibilityHint("Opens editing. Swipe left to delete.")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: CGFloat(items.count) * (Font.scaledSize(rowHeight) + 1))
    }
}

/// One row in an entry list: icon, title, detail, and a time on the right.
struct LogEntryRow: View {
    var systemImage: String
    var accent: Accent
    var title: String
    var detail: String
    var time: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 36, height: 36)
                .background(accent.fill(scheme).opacity(0.22), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(size: 15, weight: .bold)).lineLimit(1)
                Text(detail).font(.scaled(size: 13, weight: .semibold)).secondaryText().lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(time).font(.scaled(size: 15, weight: .bold)).foregroundStyle(accent.ink(scheme))
            Image(systemName: "chevron.right")
                .font(.scaled(size: 12, weight: .bold))
                .foregroundStyle(Palette(scheme: scheme).tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A bottle that fills from the bottom (0...1).
struct LogBottle: View {
    var fill: Double
    var width: CGFloat = 22
    var height: CGFloat = 44
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack(alignment: .bottom) {
            shape.fill(Palette(scheme: scheme).track)
            shape.fill(Accent.blue.fill(scheme)).frame(height: height * CGFloat(min(max(fill, 0), 1)))
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// Number formatting for the log screens.
enum LogFormat {
    static let mlPerOunce = 29.5735

    /// "1,250 ml"
    static func ml(_ value: Double) -> String { "\(grouped(Int(value.rounded()))) ml" }

    /// Water is stored in ml (what Apple Health uses) and shown in fluid ounces.
    /// "16.9 oz" for small amounts, "64 oz" from 20 oz up.
    static func oz(_ ml: Double) -> String { "\(ozNumber(ml)) oz" }

    /// "16.9", "8", "64"
    static func ozNumber(_ ml: Double) -> String {
        let oz = ml / mlPerOunce
        let tenth = (oz * 10).rounded() / 10
        if oz >= 20 || abs(tenth - tenth.rounded()) < 0.05 { return grouped(Int(oz.rounded())) }
        return String(format: "%.1f", tenth)
    }

    /// Bottle counts to the nearest half: "1½", "2", "½" (Priya U1: no
    /// "3.8 bottles"). Under a quarter of a bottle reads "0".
    static func bottles(_ value: Double) -> String {
        let halves = max((value * 2).rounded() / 2, 0)
        let whole = Int(halves)
        let half = halves - Double(whole) >= 0.5
        if whole == 0 && half { return "\u{00BD}" }
        return half ? "\(whole)\u{00BD}" : "\(whole)"
    }

    /// True when `bottles` had to round (more than a sliver off a half).
    static func bottlesRounded(_ value: Double) -> Bool {
        abs((value * 2).rounded() / 2 - value) >= 0.05
    }

    /// "½ bottle", "1 bottle", "about 2½ bottles", "2 bottles".
    static func bottlesPhrase(_ value: Double) -> String {
        let text = bottles(value)
        let plural = (value * 2).rounded() / 2 > 1 || text == "0"
        return (bottlesRounded(value) ? "about " : "") + "\(text) bottle" + (plural ? "s" : "")
    }

    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    /// "Tue 9:40pm" for entries on other days, "9:40pm" for today's app day
    /// (which runs until 4am, so 12:30am tonight is still just a time).
    static func time(_ date: Date) -> String {
        let clock = Clock.format(Clock.minutesOfDay(date))
        if AppDay.contains(date) { return clock }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday \(clock)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(clock)"
    }

    /// "Logged Latte at 3:50pm." When the time falls before the app day's
    /// rollover (a 3:50am drink logged at 4:10am), it says which day it
    /// went to, because it won't be in today's list.
    static func loggedLine(_ what: String, at date: Date) -> String {
        let clock = Clock.format(Clock.minutesOfDay(date))
        if AppDay.contains(date) { return "Logged \(what) at \(clock)." }
        let day = AppDay.day(containing: date)
        let name = Calendar.current.isDateInYesterday(day) ? "yesterday" : day.formatted(.dateTime.weekday(.wide))
        return "Logged \(what) at \(clock), for \(name). Times before \(Clock.format(AppDay.rolloverMinutes)) count toward the day before, so it\u{2019}s not in today\u{2019}s list."
    }
}

/// Edit one logged entry: its time and amount, with Save and Delete.
/// `extra` sits at the top for anything else (the kind of drink).
struct LogEditSheet<Extra: View>: View {
    var title: String
    var accent: Accent
    var unit: String
    /// The unit for amounts other than 1 ("drinks"), when it differs.
    var pluralUnit: String?
    var step: Double
    var range: ClosedRange<Double>
    var presets: [(label: String, value: Double)]
    var showsDate: Bool
    var onSave: (Date, Double) -> Void
    var onDelete: () -> Void
    var extra: Extra
    @State private var date: Date
    @State private var amount: Double
    private let original: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    init(title: String, accent: Accent, date: Date, amount: Double, unit: String, pluralUnit: String? = nil, step: Double,
         range: ClosedRange<Double>, presets: [(label: String, value: Double)] = [], showsDate: Bool = false,
         onSave: @escaping (Date, Double) -> Void, onDelete: @escaping () -> Void, @ViewBuilder extra: () -> Extra) {
        self.title = title
        self.accent = accent
        self.unit = unit
        self.pluralUnit = pluralUnit
        self.original = date
        self.step = step
        self.range = range
        self.presets = presets
        self.showsDate = showsDate
        self.onSave = onSave
        self.onDelete = onDelete
        self.extra = extra()
        _date = State(wrappedValue: date)
        _amount = State(wrappedValue: amount)
    }

    private var amountText: String {
        amount == amount.rounded() ? LogFormat.grouped(Int(amount)) : String(format: "%.1f", amount)
    }

    private var components: DatePickerComponents { showsDate ? [.date, .hourAndMinute] : .hourAndMinute }

    private var unitText: String { amount == 1 ? unit : (pluralUnit ?? unit) }

    /// A time-only edit stays in the entry's own day (times after midnight
    /// belong to the evening before, until 4am). Never later than now.
    private var dateBinding: Binding<Date> {
        Binding(get: { date },
                set: { new in
                    let placed = showsDate ? new : AppDay.place(new, inAppDayOf: original)
                    date = min(placed, .now)
                })
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    extra
                    Card {
                        HStack {
                            Text(showsDate ? "When" : "Time").font(.scaled(size: 15, weight: .bold))
                            Spacer()
                            DatePicker("Time", selection: dateBinding, displayedComponents: components)
                                .labelsHidden()
                                .tint(accent.ink(scheme))
                        }
                        .frame(minHeight: 44)
                        Text(showsDate
                             ? "Can\u{2019}t be later than now."
                             : "\(LogFormat.time(date)). Times between midnight and \(Clock.format(AppDay.rolloverMinutes)) count toward the evening before. Can\u{2019}t be later than now.")
                            .font(.scaled(size: 12)).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Card {
                        Text("Amount").font(.scaled(size: 15, weight: .bold))
                        HStack(spacing: 12) {
                            stepButton("minus", label: "Less") { amount = max(range.lowerBound, amount - step) }
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(amountText).font(.scaledNumber(30))
                                Text(unitText).font(.scaled(size: 15, weight: .semibold)).secondaryText()
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                            stepButton("plus", label: "More") { amount = min(range.upperBound, amount + step) }
                        }
                        if !presets.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(presets.indices, id: \.self) { i in
                                    Chip(title: presets[i].label, selected: amount == presets[i].value, accent: accent) {
                                        amount = presets[i].value
                                    }
                                }
                            }
                        }
                    }
                    PrimaryButton(title: "Save", accent: accent) {
                        onSave(min(date, .now), amount)
                        dismiss()
                    }
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.scaled(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Accent.pink.ink(scheme))
                            .background(p.chip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(p.background)
            .foregroundStyle(p.primary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.scaled(size: 18, weight: .bold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 48, height: 48)
                .background(accent.fill(scheme).opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(LogFormat.grouped(Int(step))) \(unit)")
    }
}

extension LogEditSheet where Extra == EmptyView {
    init(title: String, accent: Accent, date: Date, amount: Double, unit: String, pluralUnit: String? = nil, step: Double,
         range: ClosedRange<Double>, presets: [(label: String, value: Double)] = [], showsDate: Bool = false,
         onSave: @escaping (Date, Double) -> Void, onDelete: @escaping () -> Void) {
        self.init(title: title, accent: accent, date: date, amount: amount, unit: unit, pluralUnit: pluralUnit, step: step, range: range,
                  presets: presets, showsDate: showsDate, onSave: onSave, onDelete: onDelete) { EmptyView() }
    }
}
