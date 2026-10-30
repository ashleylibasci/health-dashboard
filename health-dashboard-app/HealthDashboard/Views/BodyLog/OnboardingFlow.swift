import SwiftUI
import HealthCore

/// First-run setup, kept short (Whitfield F12): welcome, your cycle (with
/// which birth control and where you are in your pack only when they
/// apply), your sleep times, done. Age is asked on the Fitness screen,
/// health conditions in Settings (and from the last step), and notification
/// permission on the last step, where it says what the alerts are for.
/// Finishing connects Health and shows what it found (D-L3), then marks her
/// onboarded, which drops her on Today.
struct OnboardingFlow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Step = .welcome
    /// Which way the last move went, so pages slide the right way.
    @State private var forward = true
    @State private var alerts: AlertsChoice = .undecided
    @FocusState private var nameFocused: Bool

    private enum AlertsChoice { case undecided, on, off }

    /// Nothing is preselected the first time: she picks her own cycle setup
    /// (`cycleSetupChosen`). On "Redo setup" her current answer shows.
    private var cycleChoice: AppData.CycleSetup? {
        store.data.cycleSetupChosen ? store.data.cycleSetup : nil
    }

    private enum Step: Hashable { case welcome, cycle, birthControl, pack, sleep, done, reading }

    /// How far the last step has got reading Apple Health (D-L3).
    @State private var reading = ReadingProgress.started

    private enum ReadingProgress: Int, Comparable {
        case started, nights, heart, finished
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .cycle: cycleStep
                    case .birthControl: birthControlStep
                    case .pack: packStep
                    case .sleep: sleepStep
                    case .done: doneStep
                    case .reading: readingStep
                    }
                }
                .id(step)
                .transition(pageTransition)
            }
            .modifier(TopBar(shown: step != .welcome && step != .reading) { topBar })
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Forward: the new page comes in from the right; back: from the left.
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    // MARK: Navigation

    private var usesBirthControl: Bool { store.data.cycleSetup == .hormonal }
    /// Pill, ring or patch: ask where she is in her pack.
    private var usesPack: Bool { store.birthControl?.hasBreakWeek == true }

    /// The steps she'll go through, from her answers so far. The birth
    /// control step stays in while she's on it, so the counter never repeats.
    private var flow: [Step] {
        var out: [Step] = [.cycle]
        if usesBirthControl || step == .birthControl || step == .pack { out.append(.birthControl) }
        if usesPack || step == .pack { out.append(.pack) }
        out += [.sleep, .done]
        return out
    }

    /// The counter treats "which birth control" and "your pack" as part of
    /// the cycle step, so picking birth control (or a pill instead of an
    /// implant) never changes the total mid-flow: "Step 2 of 3" stays "of 3".
    private var counted: [Step] { flow.filter { $0 != .birthControl && $0 != .pack } }

    private var totalSteps: Int { counted.count }

    private func number(of step: Step) -> Int {
        let s = (step == .pack || step == .birthControl) ? .cycle : step
        return (counted.firstIndex(of: s) ?? 0) + 1
    }

    private func go(_ next: Step, forward: Bool = true) {
        nameFocused = false
        self.forward = forward
        withMotion(.page) { step = next }
    }

    private func next() {
        let f = flow
        guard let i = f.firstIndex(of: step) else { go(.cycle); return }
        if i + 1 < f.count { go(f[i + 1]) }
    }

    private func back() {
        let f = flow
        guard let i = f.firstIndex(of: step), i > 0 else { go(.welcome, forward: false); return }
        go(f[i - 1], forward: false)
    }

    /// Connects Health, then shows what it found one line at a time, then
    /// drops her on Today.
    private func finish() {
        // Alerts she didn't allow stay off, so Settings never shows them on
        // without permission. Turning one on there asks then.
        if alerts != .on {
            store.data.sickAlerts = false
            store.data.peakDipNudges = false
        }
        reading = .started
        go(.reading)
        Task {
            await model.connectHealth()
            let pause: Duration = reduceMotion ? .milliseconds(400) : .milliseconds(900)
            for next in [ReadingProgress.nights, .heart, .finished] {
                try? await Task.sleep(for: pause)
                withMotion(.reveal) { reading = next }
            }
            try? await Task.sleep(for: .seconds(1.2))
            openToday()
        }
    }

    private func openToday() {
        guard !store.data.onboarded else { return }
        withMotion(.commit) { store.data.onboarded = true }
    }

    // MARK: Shared pieces

    /// Back, "Step 1 of 3" with its progress bar, and Skip on the pack step.
    /// It stays put while the pages slide under it.
    private var topBar: some View {
        let p = Palette(scheme: scheme)
        let current = number(of: step)
        return HStack(spacing: 12) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.scaled(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(p.card, in: Circle())
                    .overlay(Circle().strokeBorder(p.cardBorder))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Back")
            Spacer()
            VStack(spacing: 6) {
                Text("Step\u{00A0}\(current)\u{00A0}of\u{00A0}\(totalSteps)")
                    .font(.scaled(size: 13, weight: .semibold))
                    .secondaryText()
                    .keepsOnOneLine()
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                HStack(spacing: 4) {
                    ForEach(1...max(totalSteps, 1), id: \.self) { i in
                        ZStack(alignment: .leading) {
                            Capsule().fill(p.track)
                            Capsule().fill(Accent.indigo.ink(scheme))
                                .frame(width: i <= current ? 22 : 0)
                        }
                        .frame(width: 22, height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            .motion(.page, value: current)
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Spacer()
            if step == .pack {
                Button("Skip") { next() }
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .keepsOnOneLine()
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xs)
    }

    private func heading(_ first: String, _ second: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(first)
            Text(second).foregroundStyle(Accent.purple.ink(scheme))
        }
        .font(.headingScaled(size: 32))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(first) \(second)")
        .accessibilityAddTraits(.isHeader)
    }

    private func intro(_ text: String) -> some View {
        Text(text)
            .font(.scaled(size: 16))
            .secondaryText()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func checkmark(_ on: Bool, size: CGFloat = 24) -> some View {
        ZStack {
            Circle().fill(on ? Accent.indigo.ink(scheme) : Color.clear)
            Circle().strokeBorder(on ? Color.clear : Palette(scheme: scheme).tertiary, lineWidth: 2)
            if on {
                Image(systemName: "checkmark")
                    .font(.scaled(size: size * 0.45, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Color(hex: 0x0E1136) : .white)
            }
        }
        .frame(width: size, height: size)
        .motion(.select, value: on)
        .accessibilityHidden(true)
    }

    // MARK: Welcome

    private var welcome: some View {
        Screen(accent: .indigo, refreshes: false) {
            ZStack {
                // Example numbers, labeled as such: nothing is hers yet.
                Ring(value: Double(model.recoveryShown ?? AppModel.recoveryAnchor) / 100, accent: .indigo, lineWidth: 16,
                     label: "\(model.recoveryShown ?? AppModel.recoveryAnchor)", caption: "Example", size: 196)
                // The chips overlap the ring at accessibility sizes (Ortiz P1).
                if !typeSize.isAccessibilitySize {
                    VStack {
                        HStack {
                            Spacer()
                            welcomeChip(model.caffeineCutoffShown.map { "Latte by \(BodyLogStyle.shortTime($0))" } ?? "One small latte, early", accent: .yellow)
                        }
                        Spacer()
                        HStack {
                            welcomeChip("Sleep \(Clock.duration(model.tonightNeed.total))", accent: .purple)
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .padding(.top, 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("Your body, explained.")
                Text("Cycle included.").foregroundStyle(Accent.purple.ink(scheme))
            }
            .font(.headingScaled(size: 34))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your body, explained. Cycle included.")
            .accessibilityAddTraits(.isHeader)

            intro("Sleep, recovery, caffeine and your cycle, read from your Apple Watch. Your data stays on your phone.")

            PrimaryButton(title: "Connect Apple Health") {
                Task { await model.connectHealth() }
                go(.cycle)
            }
            .padding(.top, 8)
            Text("Apple Health asks about each kind of data: sleep, heart rate and HRV, activity, daylight, wrist temperature, breathing, VO\u{2082} max, caffeine, water and cycle tracking. The app only saves the caffeine and water you log here.")
                .font(.scaled(size: 13))
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)

            Card {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Accent.indigo.ink(scheme))
                        .frame(width: 36, height: 36)
                        .background(Accent.indigo.tint(scheme), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your cycle data stays on your phone.").font(.bodyEmphasis)
                        Text("Never uploaded by this app. Widgets you add can show it on your screen.").font(.bodyText).secondaryText()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Not a medical device. In an emergency call 911.")
                .font(.scaled(size: 13, weight: .semibold))
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func welcomeChip(_ text: String, accent: Accent) -> some View {
        Text(text)
            .font(.scaled(size: 14, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Palette(scheme: scheme).card, in: Capsule())
            .background(accent.tint(scheme), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.fill(scheme).opacity(0.35)))
    }

    // MARK: Cycle

    private struct CycleOption: Identifiable {
        let setup: AppData.CycleSetup
        let title: String
        let detail: String
        let dot: Color
        var id: AppData.CycleSetup { setup }
    }

    private var cycleOptions: [CycleOption] {
        [
            CycleOption(setup: .natural, title: "Natural cycle",
                        detail: "No birth control. Your phases are placed from the periods you log here or in Apple Health.",
                        dot: Accent.pink.fill(scheme)),
            CycleOption(setup: .hormonal, title: "Birth control",
                        detail: "Pill, ring, patch, implant, shot, or a hormonal or copper IUD. Next, pick which one.",
                        dot: Accent.indigo.fill(scheme)),
            CycleOption(setup: .irregular, title: "Irregular or not sure",
                        detail: "PCOS, a cycle that changes a lot, or you just don\u{2019}t know yet. No countdowns.",
                        dot: Color(hex: 0xFFD2BD)),
            CycleOption(setup: .notTracking, title: "Not tracking a cycle",
                        detail: "Pregnant, postpartum, menopause, or you\u{2019}d just rather not. Cycle cards stay hidden.",
                        dot: Palette(scheme: scheme).tertiary),
        ]
    }

    private var cycleStep: some View {
        Screen(accent: .purple, refreshes: false) {
            heading("Your", "cycle")
            intro("This changes what the app shows you. Every body is different, and you can change it anytime.")
            VStack(spacing: 10) {
                ForEach(cycleOptions) { option in
                    cycleCard(option)
                }
            }
            Label("Stays on your phone. Never shared, never uploaded.", systemImage: "lock.fill")
                .font(.scaled(size: 13))
                .secondaryText()
            PrimaryButton(title: "Continue") {
                if !usesBirthControl { store.data.birthControl = nil }
                next()
            }
            .disabled(cycleChoice == nil)
            .opacity(cycleChoice == nil ? 0.5 : 1)
            Text(nextAfterCycle)
                .font(.scaled(size: 13))
                .secondaryText()
                .frame(maxWidth: .infinity)
        }
    }

    private var nextAfterCycle: String {
        guard cycleChoice != nil else { return "Pick one to continue" }
        return usesBirthControl ? "Next: which birth control" : "Next: your sleep times"
    }

    private func cycleCard(_ option: CycleOption) -> some View {
        let p = Palette(scheme: scheme)
        let on = cycleChoice == option.setup
        let shape = RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
        return ZStack(alignment: .bottomTrailing) {
        Button {
            var d = store.data
            d.cycleSetup = option.setup
            d.cycleSetupChosen = true
            withMotion(.select) { store.data = d }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Circle().fill(option.dot).frame(width: 16, height: 16).padding(.top, 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title).font(.cardTitle)
                    Text(option.detail).font(.bodyText).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                checkmark(on)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(on ? Accent.indigo.fill(scheme).opacity(0.2) : p.card, in: shape)
            .overlay(shape.strokeBorder(on ? Accent.indigo.ink(scheme) : p.cardBorder, lineWidth: 2))
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: on) { _, isOn in isOn }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
            if option.setup == .irregular {
                InfoButton(title: "Irregular cycles and PCOS",
                           meaning: (ConditionCatalog.all.first { $0.name == "PCOS" }?.meaning ?? "") + " Irregular cycles can also come from stress, weight changes, the years after periods start, or for no clear reason.",
                           forYou: "Pick this if your cycle changes a lot from month to month or you have PCOS. The app counts days since your last period instead of predicting the next one. You can also add PCOS under Health conditions in Settings.")
                    .padding(4)
            }
        }
    }

    // MARK: Birth control

    private enum Ovulation: String {
        case stops = "Stops ovulation"
        case may = "May still ovulate"
        case natural = "Natural cycle"
    }

    /// Short card text for each method. The method list itself comes from
    /// HealthCore's `BirthControl`, so the saved value always matches it.
    private func shortNote(_ bc: BirthControl) -> String {
        switch bc {
        case .combinedPill: "Estrogen + progestin. Bleed in the break week."
        case .miniPill: "Progestin only. Bleeding can be unpredictable."
        case .hormonalIUD: "Mirena, Kyleena\u{2026} Periods often lighter or stop."
        case .copperIUD: "No hormones. Periods can be heavier."
        case .implant: "Nexplanon. Bleeding varies a lot."
        case .shot: "Depo-Provera, every 12\u{2013}13 weeks."
        case .ring: "NuvaRing, Annovera. Like the pill."
        case .patch: "Weekly patch. Like the pill."
        }
    }

    private func tag(_ bc: BirthControl) -> String {
        switch bc.ovulation {
        case .stopped: "Stops ovulation"
        case .sometimes: "Sometimes"
        case .mostStill: "Most still ovulate"
        case .natural: "Natural cycle"
        }
    }

    private func kind(_ bc: BirthControl) -> Ovulation {
        switch bc.ovulation {
        case .stopped: .stops
        case .sometimes, .mostStill: .may
        case .natural: .natural
        }
    }

    private func accent(for kind: Ovulation) -> Accent {
        switch kind {
        case .stops: .indigo
        case .may: .yellow
        case .natural: .mint
        }
    }

    private func choose(_ bc: BirthControl) {
        var d = store.data
        d.birthControl = bc.rawValue
        d.cycleSetup = .hormonal
        d.cycleSetupChosen = true
        store.data = d
    }

    /// What each method is, behind the ⓘ on its card.
    private func methodExplanation(_ bc: BirthControl) -> Explanation {
        let meaning: String
        switch bc {
        case .combinedPill:
            meaning = "Estrogen and progestin are the two hormones in the combined pill. Together they stop your body from releasing an egg. The bleed in your break week is a withdrawal bleed, from the pause in hormones, not a period."
        case .hormonalIUD:
            meaning = "Mirena, Kyleena, Liletta and Skyla are hormonal IUDs: a small device in the uterus that releases progestin for several years. Most people still ovulate. Periods often get lighter or stop."
        default:
            meaning = bc.note
        }
        let forYou: String
        switch bc.ovulation {
        case .stopped where bc.hasBreakWeek:
            forYou = "The app shows your pack (active days and the break) instead of cycle phases, and never predicts ovulation. Next, you can set where you are in your pack."
        case .stopped:
            forYou = "No cycle phases or period countdowns. The app keeps a history of any bleeding you log."
        case .sometimes, .mostStill:
            forYou = "The app shows rough cycle phases with no period countdown, and doesn\u{2019}t call a long gap between bleeds late."
        case .natural:
            forYou = "The app shows your cycle phases, like a natural cycle."
        }
        return Explanation(id: "method-\(bc.rawValue)", title: bc.rawValue, meaning: meaning, forYou: forYou)
    }

    private var hormonalMethods: [BirthControl] { BirthControl.allCases.filter { $0 != .copperIUD } }

    private var birthControlStep: some View {
        Screen(accent: .purple, refreshes: false) {
            heading("Which", "birth control?")
            intro("Each one changes your body differently, so the app adjusts what it shows. Methods that stop ovulation never get ovulation or period predictions.")
            // One row when it fits; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ovulationLegend(.stops)
                    ovulationLegend(.may)
                    ovulationLegend(.natural)
                    InfoButton(explanation: Self.ovulationInfo).padding(.vertical, -12)
                }
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        ovulationLegend(.stops)
                        ovulationLegend(.may)
                        ovulationLegend(.natural)
                    }
                    InfoButton(explanation: Self.ovulationInfo)
                }
            }
            SectionLabel(text: "Hormonal")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(hormonalMethods, id: \.self) { bc in
                    methodCard(bc)
                }
            }
            SectionLabel(text: "No hormones")
            methodCard(.copperIUD)
            otherOption(title: "No birth control", detail: "Natural cycle, placed from the periods you log.", setup: .natural)
            otherOption(title: "Irregular or not sure", detail: "No countdowns.", setup: .irregular)
            otherOption(title: "Not tracking a cycle", detail: "Cycle cards stay hidden.", setup: .notTracking)
            Card {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Accent.indigo.ink(scheme))
                        .accessibilityHidden(true)
                    Text("Not sure which pill you take? The name is on the pack, or ask your pharmacist. You can change this anytime.")
                        .font(.scaled(size: 14))
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PrimaryButton(title: "Continue") { next() }
                .disabled(usesBirthControl && store.birthControl == nil)
                .opacity(usesBirthControl && store.birthControl == nil ? 0.5 : 1)
            if usesBirthControl && store.birthControl == nil {
                Text("Pick one to continue")
                    .font(.scaled(size: 13))
                    .secondaryText()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func otherOption(title: String, detail: String, setup: AppData.CycleSetup) -> some View {
        let p = Palette(scheme: scheme)
        let on = store.data.cycleSetup == setup
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            var d = store.data
            d.cycleSetup = setup
            d.birthControl = nil
            d.cycleSetupChosen = true
            store.data = d
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.scaled(size: 15, weight: .bold))
                    Text(detail).font(.scaled(size: 13)).secondaryText()
                }
                Spacer(minLength: 0)
                checkmark(on, size: 20)
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(on ? Accent.indigo.fill(scheme).opacity(0.2) : p.card, in: shape)
            .overlay(shape.strokeBorder(on ? Accent.indigo.ink(scheme) : p.cardBorder, lineWidth: on ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// What the legend means. The Cycle screen's mid-cycle ⓘ is about the
    /// estimate; this one is about which methods stop ovulation.
    private static let ovulationInfo = Explanation(id: "ovulationMethods", title: "Ovulation",
        meaning: "When an egg is released, usually about 12 to 14 days before a period.",
        forYou: "Some methods stop it, some may, and some don't. The app never shows ovulation or fertile days for methods that stop it. For the rest it shows a rough mid-cycle estimate, which isn't your fertile days.")

    private func ovulationLegend(_ kind: Ovulation) -> some View {
        let a = accent(for: kind)
        return HStack(spacing: 5) {
            Circle().fill(a.ink(scheme)).frame(width: 7, height: 7)
            Text(kind.rawValue).fixedSize(horizontal: false, vertical: true)
        }
        .font(.scaled(size: 11, weight: .bold))
        .foregroundStyle(a.ink(scheme))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(a.fill(scheme).opacity(0.16), in: Capsule())
    }

    private func methodCard(_ bc: BirthControl) -> some View {
        let p = Palette(scheme: scheme)
        let on = store.birthControl == bc
        let a = accent(for: kind(bc))
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack(alignment: .bottomTrailing) {
        Button { choose(bc) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(bc.rawValue).font(.scaled(size: 15, weight: .bold))
                    Spacer(minLength: 4)
                    checkmark(on, size: 20)
                }
                Text(shortNote(bc)).font(.scaled(size: 12)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(tag(bc))
                    .font(.scaled(size: 11, weight: .bold))
                    .foregroundStyle(a.ink(scheme))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(a.fill(scheme).opacity(0.16), in: Capsule())
            }
            .multilineTextAlignment(.leading)
            .padding(12)
            .padding(.trailing, 28)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(on ? Accent.indigo.fill(scheme).opacity(0.2) : p.card, in: shape)
            .overlay(shape.strokeBorder(on ? Accent.indigo.ink(scheme) : p.cardBorder, lineWidth: 2))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
            InfoButton(explanation: methodExplanation(bc)).padding(2)
        }
    }

    // MARK: Your pack

    private var packUnit: String { store.birthControl == .combinedPill ? "pill" : "day" }

    private var packStep: some View {
        Screen(accent: .purple, refreshes: false) {
            heading("Where are you", "in your pack?")
            intro("Look at your pack: which \(packUnit) is today\u{2019}s? Then the break week and your withdrawal bleed land on the right days.")
            Card {
                PackSetupControl(showsSkip: false)
            }
            HStack(spacing: 0) {
                Text("What\u{2019}s a withdrawal\u{00A0}bleed?").font(.scaled(size: 14, weight: .semibold)).secondaryText()
                InfoButton(topic: .withdrawalBleed).padding(.vertical, -12)
            }
            PrimaryButton(title: "Continue") { next() }
            Text("Not sure? Skip it. You can set it anytime in Settings or on the Cycle screen.")
                .font(.scaled(size: 13))
                .secondaryText()
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Sleep

    private var sleepStep: some View {
        Screen(accent: .purple, refreshes: false) {
            heading("Your", "sleep times")
            intro("When do you usually go to bed, and what\u{2019}s the latest you can get up? Any times work. They set your caffeine cutoff, wake plan and smart alarm.")
            Card {
                SleepScheduleControl()
            }
            SectionLabel(text: "Set up sleep tracking").padding(.top, 4)
            Card {
                setupTip("bed.double.fill", .purple, "Turn on a sleep schedule or Sleep Focus",
                         "In the Health app, under Sleep. Apple Watch only tracks sleep when one is set up.")
                setupTip("applewatch", .indigo, "Wear your Watch to bed, snug",
                         "One finger\u{2019}s width above your wrist bone. A loose band misses heartbeats.")
                setupTip("battery.100.bolt", .mint, "Charge it before bed",
                         "Top it up while you shower or get ready, so it lasts the night.")
                setupTip("thermometer.medium", .orange, "Turn on Wrist Temperature",
                         "In the Watch app, under Health. It helps spot when you might be getting sick.")
                NavigationLink { AccuracyTipsView() } label: {
                    HStack(spacing: 6) {
                        Text("Getting accurate numbers")
                        Image(systemName: "chevron.right").font(.scaled(size: 12, weight: .bold)).accessibilityHidden(true)
                    }
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            PrimaryButton(title: "Continue") { next() }
        }
    }

    private func setupTip(_ symbol: String, _ accent: Accent, _ title: String, _ why: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 36, height: 36)
                .background(accent.tint(scheme), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.bodyEmphasis)
                Text(why).font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Done

    private var nameBinding: Binding<String> {
        Binding(get: { store.data.name ?? "" },
                set: { store.data.name = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
    }

    private var doneStep: some View {
        let p = Palette(scheme: scheme)
        return Screen(accent: .purple, refreshes: false) {
            heading("You\u{2019}re", "all set")
            intro("Your own numbers replace the example ones after 14 nights of sleep. Until then they\u{2019}re labelled Example data.")
            Card {
                AdaptiveStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your first name").font(.bodyEmphasis)
                        Text("Optional. Today greets you with it.").font(.secondary).secondaryText()
                    }
                    TextField("Name", text: nameBinding)
                        .font(.bodyText)
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Your first name, optional")
                }
            }
            alertsCard
            Card(density: .compact) {
                LinkRow(title: "Health conditions",
                        subtitle: "Optional. PCOS, PMDD, an eating-disorder history and others. Some change what the app shows. Also in Settings.",
                        systemImage: "heart.text.square.fill", accent: .pink) {
                    ConditionsView()
                }
            }
            PrimaryButton(title: "Start tracking", action: finish)
            Text("Calories (off), alcohol tracking, light mode and exams from your calendar are in Settings.")
                .font(.secondary)
                .foregroundStyle(p.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            // "Redo setup": permission she already gave shows as on.
            if alerts == .undecided, await Nudges.isAllowed() { alerts = .on }
        }
    }

    // MARK: Reading her data

    /// Nights from Apple Health in the last 30 days (`-demoReading`: 27).
    private var nightsFound: Int {
        if DemoMode.reading { return 27 }
        let start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        return model.realNightDays.filter { $0 >= start }.count
    }

    private var heartFound: Bool { DemoMode.reading || model.heartIsReal }

    /// "Reading your last 30 nights… 27 nights found, HRV from your Watch ✓",
    /// then Today. Only what was really found gets a tick.
    private var readingStep: some View {
        Screen(accent: .purple, refreshes: false) {
            heading("Reading", "your data")
                .padding(.top, Space.section)
            intro("Everything stays on your phone.")
            Card {
                readingLine(done: reading >= .nights, found: nightsFound > 0,
                            working: "Reading your last 30 nights\u{2026}",
                            result: nightsFound > 0 ? "\(nightsFound) night\(nightsFound == 1 ? "" : "s") found"
                                                    : "No nights yet. Wear your Watch to bed tonight")
                if reading >= .nights {
                    readingLine(done: reading >= .heart, found: heartFound,
                                working: "Looking for HRV\u{2026}",
                                result: heartFound ? "HRV from your Watch" : "No HRV yet. It comes after a night with your Watch")
                        .motionTransition(.reveal, edge: .top)
                }
                if reading >= .heart {
                    readingLine(done: reading >= .finished, found: true,
                                working: "Setting up Today\u{2026}", result: "Today is ready")
                        .motionTransition(.reveal, edge: .top)
                }
            }
            if nightsFound < AppModel.nightsNeeded && reading >= .nights {
                intro("Until you have \(AppModel.nightsNeeded) nights, Today shows example numbers, labelled Example data.")
                    .motionTransition(.reveal, edge: .top)
            }
            if reading == .finished {
                PrimaryButton(title: "See today", action: openToday)
                    .motionTransition(.reveal, edge: .bottom)
            }
        }
    }

    /// A spinner while it works, then a tick (or a plain dot when nothing
    /// was found) and what it found.
    private func readingLine(done: Bool, found: Bool, working: String, result: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Group {
                if !done {
                    ProgressView().controlSize(.small)
                } else if found {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Accent.mint.ink(scheme))
                } else {
                    Image(systemName: "circle.dashed").foregroundStyle(Palette(scheme: scheme).tertiary)
                }
            }
            .font(.scaled(size: 17, weight: .semibold))
            .frame(width: Font.scaledSize(22))
            .accessibilityHidden(true)
            Text(done ? result : working)
                .font(.bodyEmphasis)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Sizes.minTap)
        .accessibilityElement(children: .combine)
    }

    /// Notification permission, asked here where it says what it's for,
    /// instead of a system prompt the moment setup ends.
    private var alertsCard: some View {
        let p = Palette(scheme: scheme)
        return Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(width: 36, height: 36)
                    .background(Accent.indigo.tint(scheme), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alerts").font(.bodyEmphasis)
                    Text("A heads-up 15 minutes before your focus peak and afternoon dip, and a note when several overnight signals say you may be getting sick (at most once a day).")
                        .font(.secondary).foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            switch alerts {
            case .undecided:
                Button {
                    Task {
                        let granted = await Nudges.requestPermission()
                        withMotion(.reveal) { alerts = granted ? .on : .off }
                    }
                } label: {
                    Text("Allow alerts")
                        .font(.bodyEmphasis)
                        .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
                        .foregroundStyle(Accent.indigo.ink(scheme))
                        .background(Accent.indigo.tint(scheme), in: Capsule())
                }
                .buttonStyle(.pressable)
                Text("Or skip it: they stay off, and you can turn them on in Settings.")
                    .font(.secondary).foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .on:
                Label("Alerts on. Change them anytime in Settings.", systemImage: "checkmark.circle.fill")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.mint.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            case .off:
                Text("Alerts are off. To turn them on later, allow notifications in the iPhone\u{2019}s Settings, then in this app\u{2019}s Settings.")
                    .font(.secondary).foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The onboarding top bar (back, step counter, Skip) above the pages, so it
/// stays still while they slide. On iOS 26 it gets the system's scroll-edge
/// treatment; before that, a solid background so text never shows through.
private struct TopBar<Bar: View>: ViewModifier {
    var shown: Bool
    @ViewBuilder var bar: Bar
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .top) {
                if shown { bar }
            }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                if shown { bar.background(Palette(scheme: scheme).background.opacity(0.94)) }
            }
        }
    }
}
