import SwiftUI
import HealthCore

/// The Log tab: only logging, in one place. Caffeine (at the time you
/// choose), period or bleeding flow, water, stress, the morning check-in and
/// alcohol. Every log shows a toast with Undo for 5 seconds; each section's
/// "History" link opens its full screen for past entries and advice.
struct LogView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var toast: UndoToast?
    @State private var showsSymptoms = false
    @State private var pourKind: PourKind?
    /// Haptics: adding (alcohol), saving (flow), picking (stress,
    /// symptoms). The caffeine and water cards play their own.
    @State private var addCount = 0
    @State private var saveCount = 0
    @State private var selectCount = 0

    var body: some View {
        Screen(accent: .indigo) {
            BodyLogTabHeader("Log today")
            SampleDataBanner(forLog: true)
            caffeineSection
            if store.data.cycleSetup != .notTracking { cycleSection }
            waterSection
            stressSection
            checkInSection
            if store.data.drinksTracking { alcoholSection }
        }
        .undoToast($toast)
        .sensoryFeedback(.increase, trigger: addCount)
        .sensoryFeedback(.success, trigger: saveCount)
        .sensoryFeedback(.selection, trigger: selectCount)
    }

    private var numericTransition: ContentTransition { reduceMotion ? .opacity : .numericText() }

    // MARK: Caffeine

    private var caffeineSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LogSectionHeader(title: "Caffeine", systemImage: "cup.and.saucer.fill", accent: .yellow) {
                HistoryLink { CaffeineView() }
            }
            CaffeineQuickLog(toast: $toast)
        }
    }

    // MARK: Period or bleeding

    /// "Bleeding" on a method where bleeds aren't periods, "Period" otherwise.
    private var bleedingWord: String {
        model.usesBleedingWording || model.usesPackWording ? "Bleeding" : "Period"
    }

    private var cal: Calendar { Calendar.current }

    private var flowToday: AppData.Flow? {
        store.data.flowLog.last { cal.isDateInToday($0.date) }?.flow
    }

    private var symptomsToday: [String] {
        store.data.symptomLog.last { cal.isDateInToday($0.date) }?.symptoms ?? []
    }

    private var symptomOptions: [String] {
        var list = CycleLogView.symptomOptions
        if store.data.conditions.contains("PCOS") { list.append("Hair changes") }
        for s in symptomsToday where !list.contains(s) { list.append(s) }
        return list
    }

    private static func flowLabel(_ f: AppData.Flow) -> String { f == .none ? "None" : f.rawValue }

    private var cycleSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LogSectionHeader(title: bleedingWord, systemImage: "drop.fill", accent: .pink) {
                HistoryLink { CycleLogView() }
            }
            IronPromptCallout()
            PillLogCallouts()
            Card {
                AdaptiveStack(spacing: Space.xs, alignment: .firstTextBaseline) {
                    Text("Flow today").font(.bodyEmphasis)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: Space.s) }
                    Text(flowToday.map { "Saved: \(Self.flowLabel($0).lowercased())" } ?? "One tap saves it")
                        .font(.secondary).secondaryText()
                        .contentTransition(.opacity)
                        .motion(.select, value: flowToday)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s),
                                         count: typeSize.isAccessibilitySize ? 2 : 3), spacing: Space.s) {
                    ForEach(AppData.Flow.allCases, id: \.self) { f in
                        flowChip(f)
                    }
                }
                if flowToday == .heavy {
                    // One ACOG wording everywhere, with the urgent tier (Okafor H).
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(CycleCare.heavyBleeding)
                            .font(.secondary).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                        Text(CycleCare.heavyBleedingUrgent)
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(Accent.coral.ink(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .motionTransition(.reveal, edge: .top)
                }
                Button {
                    withMotion(.reveal) { showsSymptoms.toggle() }
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(showsSymptoms ? "Hide symptoms" : symptomsToday.isEmpty ? "Add symptoms" : "Symptoms (\(symptomsToday.count))")
                        Image(systemName: "chevron.down")
                            .font(.scaled(size: 11, weight: .bold))
                            .rotationEffect(.degrees(showsSymptoms ? 180 : 0))
                            .accessibilityHidden(true)
                        Spacer()
                    }
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.pink.ink(scheme))
                    .frame(minHeight: Sizes.minTap)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsSymptoms ? "Expanded" : "Collapsed")
                if showsSymptoms {
                    FlowLayout(spacing: Space.s, lineSpacing: Space.s) {
                        ForEach(symptomOptions, id: \.self) { s in
                            symptomChip(s)
                        }
                    }
                    .motionTransition(.reveal, edge: .top)
                }
            }
            .motion(.reveal, value: flowToday == .heavy)
        }
    }

    /// Selected chips: white on the deep ink in light mode, near-black on
    /// the bright fill in dark mode.
    private func chipColors(_ on: Bool) -> (fill: Color, text: Color) {
        let p = Palette(scheme: scheme)
        if on { return scheme == .dark ? (Accent.pink.fill(.dark), Color(hex: 0x1A0E00)) : (Accent.pink.ink(.light), .white) }
        return (p.chip, p.primary)
    }

    private func flowChip(_ f: AppData.Flow) -> some View {
        let on = flowToday == f
        let colors = chipColors(on)
        let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        return Button { setFlow(on ? nil : f) } label: {
            Text(Self.flowLabel(f))
                .font(.bodyEmphasis)
                .keepsOnOneLine(minimumScale: 0.7)
                .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
                .padding(.horizontal, Space.xs)
                .foregroundStyle(colors.text)
                .background(colors.fill, in: shape)
                .overlay(shape.strokeBorder(on ? colors.fill : Palette(scheme: scheme).cardBorder))
                .motion(.select, value: on)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(f == .none ? "No flow" : "\(f.rawValue) flow")
        .accessibilityHint(on ? "Clears today\u{2019}s flow" : "Saves it for today")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Saves today's flow straight away (one entry per day, replacing what
    /// was there), with Undo putting back what was there before.
    private func setFlow(_ f: AppData.Flow?) {
        let before = store.data.flowLog
        var data = store.data
        data.flowLog.removeAll { cal.isDateInToday($0.date) }
        if let f { data.flowLog.append(.init(date: .now, flow: f)) }
        data.flowLog.sort { $0.date < $1.date }
        withMotion(.select) { store.data = data }
        let message = f.map { $0 == .none ? "Saved no flow for today." : "Saved \($0.rawValue.lowercased()) flow for today." }
            ?? "Cleared today\u{2019}s flow."
        toast = UndoToast(message) { withMotion(.undo) { store.data.flowLog = before } }
        saveCount += 1
    }

    private func symptomChip(_ s: String) -> some View {
        let on = symptomsToday.contains(s)
        let colors = chipColors(on)
        return Button { toggleSymptom(s) } label: {
            Text(s)
                .font(.scaled(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: Sizes.minTap)
                .foregroundStyle(colors.text)
                .background(colors.fill, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? colors.fill : Palette(scheme: scheme).cardBorder))
                .motion(.select, value: on)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggleSymptom(_ s: String) {
        let before = store.data.symptomLog
        var list = symptomsToday
        if let i = list.firstIndex(of: s) { list.remove(at: i) } else { list.append(s) }
        let ordered = symptomOptions.filter { list.contains($0) }
        var data = store.data
        let existing = data.symptomLog.last { cal.isDateInToday($0.date) }
        data.symptomLog.removeAll { cal.isDateInToday($0.date) }
        if !ordered.isEmpty { data.symptomLog.append(.init(date: existing?.date ?? .now, symptoms: ordered)) }
        data.symptomLog.sort { $0.date < $1.date }
        store.data = data
        let added = ordered.contains(s)
        toast = UndoToast(added ? "Added \(s.lowercased()) to today." : "Removed \(s.lowercased()) from today.") {
            withMotion(.undo) { store.data.symptomLog = before }
        }
        selectCount += 1
    }

    // MARK: Water

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LogSectionHeader(title: "Water", systemImage: "drop.fill", accent: .blue) {
                HistoryLink { WaterView() }
            }
            WaterQuickLog(toast: $toast)
        }
    }

    // MARK: Stress

    private var stressSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LogSectionHeader(title: "Stress", systemImage: "waveform.path", accent: .orange) {
                HistoryLink { StressView() }
            }
            Card {
                HStack(spacing: 0) {
                    Text("How stressed do you feel?").font(.bodyEmphasis)
                    InfoButton(title: "How stressed do you feel?",
                               meaning: "A quick 1 to 5 rating of how stressed you feel right now. 1 is very calm, 5 is very stressed.",
                               forYou: "The Stress screen shows it next to what your heart rate says, so you can see whether the two agree. Log again any time; the latest one counts for today.")
                        .padding(.vertical, -12)
                }
                Text("1 very calm \u{00B7} 5 very stressed").font(.secondary).secondaryText()
                HStack(spacing: Space.s) {
                    ForEach(1...5, id: \.self) { level in
                        stressButton(level)
                    }
                }
                if model.feltStressedToday {
                    // B6: caffeine raises anxiety, more so in big doses.
                    Text(stressCaffeineLine)
                        .font(.secondary).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                        .motionTransition(.reveal, edge: .top)
                }
            }
            .motion(.reveal, value: model.feltStressedToday)
        }
    }

    /// Today's caffeine beside a stressed check-in: "Caffeine today:
    /// 230 mg. Big doses can feel like anxiety."
    private var stressCaffeineLine: String {
        let mg = model.caffeineMgToday
        if mg > CaffeineModel.lowerGuideMg { return "Caffeine today: \(mg) mg. Big doses can feel like anxiety." }
        return mg == 0 ? "No caffeine today." : "Caffeine today: \(mg) mg."
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
        let p = Palette(scheme: scheme)
        let on = model.stressLoggedToday == level
        let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        let fill = scheme == .dark ? Accent.orange.fill(.dark) : Accent.orange.ink(.light)
        return Button {
            let entry = AppData.MoodEntry(date: .now, stress: level)
            withMotion(.select) { store.data.moodLog.append(entry) }
            toast = UndoToast("Logged stress \(level), \(Self.stressWord(level)).") {
                withMotion(.undo) { store.data.moodLog.removeAll { $0.id == entry.id } }
            }
            selectCount += 1
        } label: {
            Text("\(level)")
                .font(.numberM)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(on ? (scheme == .dark ? Color(hex: 0x1A0E00) : .white) : p.primary)
                .background(on ? fill : p.chip, in: shape)
                .overlay(shape.strokeBorder(on ? fill : p.cardBorder))
                .motion(.select, value: on)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Stress \(level), \(Self.stressWord(level))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Check-in

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LogSectionHeader(title: "Check-in", systemImage: "sun.max.fill", accent: .orange)
            Card(density: .compact) {
                LinkRow(title: "Morning check-in", subtitle: checkInSubtitle,
                        systemImage: "sun.max.fill", accent: .orange) {
                    CheckInView()
                }
            }
        }
    }

    private var checkInSubtitle: String {
        if let today = store.checkIn(on: .now) { return "Done today \u{00B7} \(today.awake) of 5 awake" }
        if !model.canCheckInNow { return "Check in after you wake up" }
        // "How awake were you this morning?" at 5pm asks about a morning
        // long gone (design review F28): a quiet line, still tappable.
        if model.now >= 720 { return "Missed today \u{00B7} back tomorrow" }
        return CheckInView.prompt + " 10 seconds."
    }

    // MARK: Alcohol

    private static let quickKinds = ["Wine", "Beer", "Seltzer", "Cocktail", "Shot"]

    /// A kind whose pour sheet is open.
    private struct PourKind: Identifiable {
        var kind: String
        var id: String { kind }
    }

    /// Standard drinks today: a red cup of wine counts as about 3.
    private var alcoholToday: Double { model.alcoholDrinksToday }

    private var alcoholSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // What one drink is: in the ⓘ, not a paragraph on the card (Amara 21).
            LogSectionHeader(title: "Alcohol", systemImage: "wineglass.fill", accent: .purple) {
                InfoButton(topic: .alcohol).padding(.vertical, -12)
                HistoryLink { DrinksView() }
            }
            Card(accent: .purple) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tap what you had").font(.bodyEmphasis)
                    Spacer(minLength: Space.s)
                    Text(alcoholToday == 0 ? "None today" : "\(DrinksView.drinksPhrase(alcoholToday)) today")
                        .font(.secondary).secondaryText()
                        .contentTransition(numericTransition)
                        .motion(.log, value: alcoholToday)
                }
                FlowLayout(spacing: Space.s) {
                    ForEach(Self.quickKinds, id: \.self) { kind in
                        Button { pourKind = PourKind(kind: kind) } label: {
                            Label(kind, systemImage: "plus")
                                .font(.scaled(size: 14, weight: .bold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: Sizes.minTap)
                                .foregroundStyle(Accent.purple.onTint(scheme))
                                .background(Accent.purple.fill(scheme).opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Log \(kind.lowercased()), now")
                        .accessibilityHint("Pick the pour: a glass, a can, a red cup")
                    }
                }
                AlcoholSafetyNote()
            }
            // How big a pour: one tap on the picture logs it (D2).
            .bottomSheet(item: $pourKind, title: { "How big a pour of \($0.kind.lowercased())?" }) { item in
                Text("Logs now. Party pours are often 2 or 3 standard drinks.")
                    .font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                PourChoices(kind: item.kind, selection: .constant("")) { pour in
                    pourKind = nil
                    logAlcohol(pour)
                }
            }
        }
    }

    private func logAlcohol(_ pour: AlcoholPour) {
        let entry = AppData.AlcoholEntry(date: .now, kind: pour.kind, count: 1, pour: pour.id)
        withMotion(.log) { store.data.alcoholLog.append(entry) }
        let size = pour.isStandard ? "" : " (\(DrinksView.drinksPhrase(pour.standardDrinks)))"
        toast = UndoToast("Logged \(entry.phrase)\(size) at \(Clock.format(model.now)).") {
            withMotion(.undo) { store.data.alcoholLog.removeAll { $0.id == entry.id } }
        }
        addCount += 1
    }
}

// MARK: - Shared by the Log, Caffeine, Water and Drinks screens

/// The caffeine log card, on the Log tab and on the Caffeine screen: one
/// component that looks and works the same in both (design review F27).
/// When she had it is one pill (`LogTimeMenu`); her first three saved
/// drinks are one-tap rows; the rest, the common drinks and "New caffeine
/// drink" are in a More drinks sheet. Logging shows the Undo toast through
/// `toast`.
///
/// Only the title differs: on the Log tab (`compact == false`) it's
/// today's total; on the Caffeine screen, whose summary has the total,
/// it's "Log caffeine".
struct CaffeineQuickLog: View {
    @Binding var toast: UndoToast?
    var compact = false
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var time: LogTime = .now
    /// Small to extra large; back to regular after each log, like the time.
    @State private var size: DrinkSize = .regular
    @State private var showsMore = false
    @State private var addCount = 0
    /// Bounces a drink's "+" when it's logged.
    @State private var bounces: [UUID: Int] = [:]
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let shownSaved = 3

    private var shownDrinks: [Drink] { Array(store.data.savedDrinks.prefix(Self.shownSaved)) }

    /// Saved drinks past the first three, then common drinks she hasn't saved.
    private var moreDrinks: [Drink] {
        let saved = Set(store.data.savedDrinks.map(\.name))
        return Array(store.data.savedDrinks.dropFirst(Self.shownSaved)) + Drink.common.filter { !saved.contains($0.name) }
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
        VStack(spacing: 0) {
            titleRow(p)
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            Divider().overlay(p.cardBorder)
            ForEach(shownDrinks) { drink in
                drinkButton(drink)
                Divider().overlay(p.cardBorder)
            }
            Button { showsMore = true } label: {
                plainRowLabel(title: "More drinks", systemImage: "ellipsis")
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Common drinks, and a new caffeine drink")
        }
        .background(Accent.yellow.tint(scheme), in: shape)
        .sensoryFeedback(.increase, trigger: addCount)
        .bottomSheet(isPresented: $showsMore, title: "More drinks") {
            moreSheet
                .environmentObject(model)
                .environmentObject(store)
        }
    }

    /// The title, then the size and time pills; the pills move under the
    /// title when they don't fit beside it (large text sizes).
    @ViewBuilder
    private func titleRow(_ p: Palette) -> some View {
        let pills = HStack(spacing: Space.s) {
            DrinkSizeMenu(size: $size)
            LogTimeMenu(time: $time, accent: .yellow)
        }
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.s) {
                title(p)
                pills
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) {
                    title(p)
                    Spacer(minLength: Space.s)
                    pills
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    title(p)
                    pills
                }
            }
        }
    }

    @ViewBuilder
    private func title(_ p: Palette) -> some View {
        if compact {
            Text("Log caffeine").font(.cardTitle).accessibilityAddTraits(.isHeader)
                .fixedSize()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("\(model.caffeineMgToday)")
                    .font(.numberM)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .motion(.log, value: model.caffeineMgToday)
                Text("mg today").font(.secondary).foregroundStyle(p.secondary)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
    }

    private var newDrinkLink: some View {
        NavigationLink { CustomDrinkView() } label: {
            plainRowLabel(title: "New caffeine drink", systemImage: "plus")
        }
        .buttonStyle(.pressable)
    }

    private func plainRowLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: systemImage)
                .font(.scaled(size: 15, weight: .bold))
                .frame(width: Sizes.icon, height: Sizes.icon)
                .background(Accent.yellow.fill(scheme).opacity(0.24), in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.bodyEmphasis)
            Spacer()
        }
        .foregroundStyle(Accent.yellow.onTint(scheme))
        .padding(.horizontal, Space.l)
        .frame(minHeight: Sizes.tallRow)
        .contentShape(Rectangle())
    }

    private var moreSheet: some View {
        let p = Palette(scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
        return VStack(alignment: .leading, spacing: Space.m) {
            Text(size == .regular ? "Logs \(time.phrase)" : "Logs \(size.label.lowercased()) \(time.phrase)")
                .font(.secondary).foregroundStyle(p.secondary)
            VStack(spacing: 0) {
                ForEach(moreDrinks) { drink in
                    drinkButton(drink) { showsMore = false }
                    Divider().overlay(p.cardBorder)
                }
                newDrinkLink
            }
            .background(Accent.yellow.tint(scheme), in: shape)
            Text(CaffeineWaterCopy.typicalAmounts)
                .font(.secondary).foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One drink as a row; a tap logs it at the chosen time (then `done`).
    private func drinkButton(_ drink: Drink, then done: (() -> Void)? = nil) -> some View {
        Button {
            log(drink)
            done?()
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: BodyLogStyle.symbol(for: drink.icon))
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(BodyLogStyle.accent(for: drink.icon).ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(BodyLogStyle.accent(for: drink.icon).fill(scheme).opacity(0.22), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(drink.name)
                        .font(.bodyEmphasis)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("\(size.mg(drink.caffeineMg)) mg").font(.secondary).secondaryText()
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                            .motion(.dataSwap, value: size)
                        if drink.isCustom { CustomDrinkBadge(accent: .purple) }
                    }
                }
                Spacer(minLength: Space.s)
                Image(systemName: "plus")
                    .font(.scaled(size: 14, weight: .bold))
                    .foregroundStyle(Accent.yellow.onTint(scheme))
                    .frame(width: 32, height: 32)
                    .background(Accent.yellow.fill(scheme).opacity(0.24), in: Circle())
                    .symbolEffect(.bounce, value: bounces[drink.id, default: 0])
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Add \(Self.name(drink, size: size)), \(size.mg(drink.caffeineMg)) mg, \(time.phrase)")
        .contextMenu {
            if store.data.savedDrinks.contains(where: { $0.id == drink.id }) {
                Button(role: .destructive) {
                    store.data.savedDrinks.removeAll { $0.id == drink.id }
                    model.pushToWatch()
                } label: {
                    Label("Remove from My caffeine drinks", systemImage: "trash")
                }
            }
        }
    }

    /// "Latte", or "Latte (large)" in another size.
    static func name(_ drink: Drink, size: DrinkSize) -> String {
        size == .regular ? drink.name : "\(drink.name) (\(size.label.lowercased()))"
    }

    private func log(_ drink: Drink) {
        let chosen = time
        let chosenSize = size
        let id = UUID()
        withMotion(.log) {
            model.logDrink(id: id, drinkID: drink.id, name: Self.name(drink, size: chosenSize),
                           mg: chosenSize.mg(drink.caffeineMg), at: chosen.date, saveToHealth: true)
        }
        let when = store.data.drinkLog.first { $0.id == id }?.date ?? .now
        let what = chosenSize == .regular ? LogFormat.midSentence(drink)
            : "\(chosenSize.label.lowercased()) \(LogFormat.midSentence(drink)) (\(chosenSize.mg(drink.caffeineMg)) mg)"
        var message = LogFormat.loggedLine(what, time: chosen, at: when)
        // Past today's cutoff: say so here, as the Watch does. The advice
        // itself is on the Caffeine screen.
        if AppDay.contains(when) {
            let t = model.appDayMinutes(when)
            if let cutoff = model.caffeineCutoffShown, t > cutoff {
                message += " Past today\u{2019}s \(Clock.format(cutoff)) cutoff."
            } else if model.caffeineCutoffShown == nil, model.caffeineAtBedtime >= 25 {
                message += " About \(model.caffeineAtBedtime) mg will be left at bedtime."
            }
        }
        toast = UndoToast(message) { withMotion(.undo) { model.deleteDrink(id) } }
        time = .now
        size = .regular
        addCount += 1
        bounces[drink.id, default: 0] += 1
    }
}

/// The drink size as one pill ("Regular ▾"), next to the time: small,
/// regular, large or extra large, compared with the drink as listed, with
/// the coffee-shop names that match (design review D4).
struct DrinkSizeMenu: View {
    @Binding var size: DrinkSize
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Menu {
            Section("Coffee shop: tall is regular, grande large, venti extra large") {
                ForEach(DrinkSize.allCases, id: \.self) { s in
                    Button { size = s } label: {
                        if s == size { Label(Self.menuLabel(s), systemImage: "checkmark") } else { Text(Self.menuLabel(s)) }
                    }
                }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Text(size.label).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.scaled(size: 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(.bodyEmphasis)
            .foregroundStyle(Accent.yellow.onTint(scheme))
            .padding(.horizontal, Space.m)
            .frame(minHeight: Sizes.minTap)
            .background(Accent.yellow.fill(scheme).opacity(size == .regular ? 0.12 : 0.24), in: Capsule())
            .fixedSize()
        }
        .accessibilityLabel("Size")
        .accessibilityValue(size.label)
        .sensoryFeedback(.selection, trigger: size)
    }

    /// "Large · 1⅓× the caffeine".
    static func menuLabel(_ s: DrinkSize) -> String {
        switch s {
        case .small: return "Small \u{00B7} \u{2154} the caffeine"
        case .regular: return "Regular \u{00B7} as listed"
        case .large: return "Large \u{00B7} 1\u{2153}\u{00D7} the caffeine"
        case .extraLarge: return "Extra large \u{00B7} 2\u{00D7} the caffeine"
        }
    }
}

/// The water card, on the Log tab and on the Water screen: "+ 1 bottle"
/// and "+ ½ bottle", logged now. On the Log tab it leads with the bottles
/// and today's total; on the Water screen (whose summary has them) it's
/// just the buttons, with a row for an earlier time or another amount
/// (`onMore`).
struct WaterQuickLog: View {
    @Binding var toast: UndoToast?
    var showsTotal = true
    var onMore: (() -> Void)? = nil
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addCount = 0
    @State private var goalCount = 0

    /// Bottles drawn: up to the goal, or (with an eating-disorder history,
    /// no goal) just the ones she's had.
    private var bottleCount: Int {
        let n = model.hidesEffortTargets ? model.waterBottlesToday : model.waterGoalBottles
        return max(1, min(Int(n.rounded(.up)), 8))
    }

    private var waterText: String {
        model.hidesEffortTargets
            ? "\(LogFormat.bottlesPhrase(model.waterBottlesToday)) today"
            : "\(LogFormat.bottles(model.waterBottlesToday)) of \(LogFormat.bottlesPhrase(model.waterGoalBottles))"
    }

    var body: some View {
        Card(accent: .blue) {
            if showsTotal { totalRow }
            // Stacked at the accessibility sizes, so "½ bottle" isn't
            // broken over two lines beside a one-line "1 bottle".
            AdaptiveStack(spacing: Space.s) {
                waterButton("1 bottle", bottles: 1)
                waterButton("\u{00BD} bottle", bottles: 0.5)
            }
            if let onMore {
                Button(action: onMore) {
                    HStack(spacing: Space.xs) {
                        Text("Earlier, or another amount")
                        Spacer(minLength: Space.s)
                        Image(systemName: "chevron.right")
                            .font(.scaled(size: 13, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.blue.ink(scheme))
                    .frame(minHeight: Sizes.minTap)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.increase, trigger: addCount)
        .sensoryFeedback(.success, trigger: goalCount)
    }

    private var totalRow: some View {
        HStack(spacing: Space.s) {
            ForEach(0..<bottleCount, id: \.self) { i in
                LogBottle(fill: min(max(model.waterBottlesToday - Double(i), 0), 1))
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: Space.xxs) {
                Text(LogFormat.oz(model.waterTodayML))
                    .font(.numberM)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .motion(.log, value: model.waterTodayML)
                if !model.hidesEffortTargets {
                    Text("of \(LogFormat.oz(model.waterGoalTodayML))").font(.secondary).secondaryText()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water, \(waterText), \(LogFormat.oz(model.waterTodayML))")
    }

    private func addWater(_ bottles: Double) {
        let id = UUID()
        let ml = store.data.bottleSizeML * bottles
        let wasUnderGoal = model.waterTodayML < model.waterGoalTodayML
        withMotion(.log) { model.addWater(ml: ml, id: id) }
        var message = "Added \(LogFormat.oz(ml)) at \(Clock.format(model.now))."
        if !model.hidesEffortTargets, wasUnderGoal, model.waterTodayML >= model.waterGoalTodayML {
            message += " That\u{2019}s today\u{2019}s goal."
            goalCount += 1
        } else {
            addCount += 1
        }
        toast = UndoToast(message) { withMotion(.undo) { model.deleteWater(id) } }
    }

    private func waterButton(_ title: String, bottles: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        return Button { addWater(bottles) } label: {
            Label(title, systemImage: "plus")
                .font(.bodyEmphasis)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Accent.blue.onTint(scheme))
                .background(Accent.blue.fill(scheme).opacity(0.2), in: shape)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Add \(title) of water, \(LogFormat.oz(store.data.bottleSizeML * bottles)), now")
    }
}

/// "When did you have it?" as one pill ("Now ▾", "30m ago", "9:10am") that
/// opens a menu of the same presets as `LogTimeSelector`, plus another
/// time in a sheet. For log cards, where the always-open chips cost a row
/// (the caffeine card on the Log tab and Caffeine screen, and Alcohol).
struct LogTimeMenu: View {
    @Binding var time: LogTime
    var accent: Accent
    @State private var picking = false
    @Environment(\.colorScheme) private var scheme

    private var label: String {
        switch time {
        case .ago(0): return "Now"
        case let .ago(minutes): return "\(LogTime.presetLabel(minutes)) ago"
        case let .exact(date): return Clock.format(Clock.minutesOfDay(date))
        }
    }

    var body: some View {
        Menu {
            ForEach(LogTime.presets, id: \.self) { minutes in
                Button(LogTime.spokenLabel(minutes)) { time = .ago(minutes) }
            }
            Button("Another time\u{2026}") { picking = true }
        } label: {
            HStack(spacing: Space.xs) {
                Text(label).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.scaled(size: 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(.bodyEmphasis)
            .foregroundStyle(accent.onTint(scheme))
            .padding(.horizontal, Space.m)
            .frame(minHeight: Sizes.minTap)
            .background(accent.fill(scheme).opacity(0.24), in: Capsule())
            .fixedSize()
        }
        .accessibilityLabel("When you had it")
        .accessibilityValue(time.phrase)
        .sensoryFeedback(.selection, trigger: time)
        .logTimeWheel(isPresented: $picking, time: $time)
    }
}

extension View {
    /// "When did you have it?": a time wheel in a sheet, for any time other
    /// than the presets. Picks the most recent time that clock time came round.
    func logTimeWheel(isPresented: Binding<Bool>, time: Binding<LogTime>) -> some View {
        bottomSheet(isPresented: isPresented, title: "When did you have it?") {
            DatePicker("Time", selection: Binding(get: { time.wrappedValue.date },
                                                  set: { time.wrappedValue = .exact(LogTime.past($0)) }),
                       displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            Text("Times between midnight and \(Clock.format(AppDay.rolloverMinutes)) count toward the evening before.")
                .font(.secondary).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A thin gauge in a `SummaryHeader`'s footer: today against a ceiling
/// (caffeine's 400 mg) or a goal (water), with a caption under it. A bar,
/// not a ring: a ring a third full read as cut off.
struct SummaryMeter: View {
    /// 0 to 1; more than 1 fills the bar.
    var fraction: Double
    var accent: Accent
    var caption: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let p = Palette(scheme: scheme)
        let ax = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track)
                    Capsule().fill(accent.fill(scheme))
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                        .motion(.fill, value: fraction)
                }
            }
            .frame(height: 8)
            Text(caption)
                .font(.secondary).fontWeight(.semibold)
                .foregroundStyle(p.secondary)
                .lineLimit(ax ? nil : 1).minimumScaleFactor(ax ? 1 : 0.8)
                .fixedSize(horizontal: false, vertical: ax)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
    }
}

/// When something was had: a preset ("now", "30 min ago"…) or a picked time.
enum LogTime: Hashable {
    /// Minutes before now; 0 is now. Resolved when logging, so "Now" is
    /// the moment she taps, not when the screen opened.
    case ago(Int)
    case exact(Date)

    static let now = LogTime.ago(0)
    static let presets = [0, 30, 60, 120]

    /// "Now", "30m", "1h", "2h".
    static func presetLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "Now" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }

    /// "Now", "30 minutes ago", "1 hour ago" for VoiceOver.
    static func spokenLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "Now" }
        if minutes < 60 { return "\(minutes) minutes ago" }
        return minutes == 60 ? "1 hour ago" : "\(minutes / 60) hours ago"
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
    @State private var picking = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title above "Other [time]" at large text sizes, so neither is
            // squeezed into a few letters per line.
            LabeledControlRow(spacing: 8) {
                Text(title).font(.scaled(size: 13, weight: .bold)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            } control: {
                // The picked time in the app's own format ("5:03pm"), not the
                // system picker's "5:03 PM" (design review F26).
                Button { picking = true } label: {
                    HStack(spacing: 8) {
                        Text("Other").font(.scaled(size: 13)).secondaryText()
                            .keepsOnOneLine()
                        Text(Clock.format(Clock.minutesOfDay(time.date)))
                            .font(.bodyEmphasis)
                            .foregroundStyle(accent.ink(scheme))
                            .keepsOnOneLine()
                            .padding(.horizontal, Space.m)
                            .frame(minHeight: Sizes.minTap)
                            .background(Palette(scheme: scheme).chip, in: Capsule())
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Pick another time")
                .accessibilityValue(Clock.format(Clock.minutesOfDay(time.date)))
            }
            // Four equal chips, "Now / 30m / 1h / 2h"; two rows of two at
            // the largest text sizes.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s),
                                     count: typeSize.isAccessibilitySize ? 2 : 4), spacing: Space.s) {
                ForEach(LogTime.presets, id: \.self) { minutes in
                    chip(minutes)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: time)
        .logTimeWheel(isPresented: $picking, time: $time)
    }

    private func chip(_ minutes: Int) -> some View {
        let p = Palette(scheme: scheme)
        let on = time == .ago(minutes)
        let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        // Light: white on the deep ink; dark: near-black on the bright fill.
        let fill = scheme == .dark ? accent.fill(.dark) : accent.ink(.light)
        return Button { withMotion(.select) { time = .ago(minutes) } } label: {
            Text(LogTime.presetLabel(minutes))
                .font(.bodyEmphasis)
                .keepsOnOneLine(minimumScale: 0.7)
                .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
                .foregroundStyle(on ? (scheme == .dark ? Color(hex: 0x1A0E00) : .white) : p.primary)
                .background(on ? fill : p.chip, in: shape)
                .overlay(shape.strokeBorder(on ? fill : p.cardBorder))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(LogTime.spokenLabel(minutes))
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
                Text(title).font(.scaled(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.scaled(size: 13, weight: .semibold)).secondaryText().lineLimit(1).minimumScaleFactor(0.7)
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
                .motion(.fill, value: fill)
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

    /// Bottle counts to the nearest quarter: "1½", "2¾", "¼" (Priya U1: no
    /// "3.8 bottles"; round 3: 2.67 isn't "2½", which falls 4 oz short).
    /// Under an eighth of a bottle reads "0".
    static func bottles(_ value: Double) -> String {
        let quarters = Int(max((value * 4).rounded(), 0))
        let whole = quarters / 4
        let part = ["", "\u{00BC}", "\u{00BD}", "\u{00BE}"][quarters % 4]
        if whole == 0 && !part.isEmpty { return part }
        return "\(whole)\(part)"
    }

    /// True when `bottles` had to round (more than a sliver off a quarter).
    static func bottlesRounded(_ value: Double) -> Bool {
        abs((value * 4).rounded() / 4 - value) >= 0.05
    }

    /// "½ bottle", "1 bottle", "about 2¾ bottles", "2 bottles".
    static func bottlesPhrase(_ value: Double) -> String {
        let text = bottles(value)
        let plural = (value * 4).rounded() / 4 > 1 || text == "0"
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

    /// A drink's name in the middle of a sentence: "latte", "drip coffee",
    /// but "Red Bull", "Diet Coke" and her own drinks as she wrote them.
    static func midSentence(_ drink: Drink) -> String {
        let name = drink.name
        guard !drink.isCustom, let first = name.first,
              !name.dropFirst().contains(where: \.isUppercase) else { return name }
        return first.lowercased() + name.dropFirst()
    }

    /// "Logged latte at 3:50pm.", echoing the time she chose: "30 min ago
    /// (2:40pm)" for a preset, "for 8:15am, the time you picked" for a
    /// picked time, so the message never looks like it ignored her choice.
    static func loggedLine(_ what: String, time: LogTime, at date: Date) -> String {
        guard AppDay.contains(date) else { return loggedLine(what, at: date) }
        let clock = Clock.format(Clock.minutesOfDay(date))
        switch time {
        case .ago(0): return "Logged \(what) at \(clock)."
        case let .ago(minutes):
            let ago = minutes < 60 ? "\(minutes) min ago" : minutes == 60 ? "1 hour ago" : "\(minutes / 60) hours ago"
            return "Logged \(what), \(ago) (\(clock))."
        case .exact: return "Logged \(what) for \(clock), the time you picked."
        }
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
                        LabeledControlRow {
                            Text(showsDate ? "When" : "Time").font(.scaled(size: 15, weight: .bold))
                        } control: {
                            DatePicker("Time", selection: dateBinding, displayedComponents: components)
                                .labelsHidden()
                                .tint(accent.ink(scheme))
                                .accessibilityLabel(showsDate ? "When" : "Time")
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
                                Text(amountText).font(.scaledNumber(30)).keepsOnOneLine()
                                Text(unitText).font(.scaled(size: 15, weight: .semibold)).secondaryText().keepsOnOneLine()
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
