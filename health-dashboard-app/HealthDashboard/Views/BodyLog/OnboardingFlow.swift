import SwiftUI
import HealthCore

/// First-run setup: welcome, about you, cycle, birth control, your pack
/// (pill, ring, patch), health conditions, sleep, preferences. Finishing
/// marks her onboarded and connects Health.
struct OnboardingFlow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("appearance") private var appearance = "dark"

    @State private var step: Step = .welcome
    @FocusState private var nameFocused: Bool

    /// Nothing is preselected the first time: she picks her own cycle setup
    /// (`cycleSetupChosen`). On "Redo setup" her current answer shows.
    private var cycleChoice: AppData.CycleSetup? {
        store.data.cycleSetupChosen ? store.data.cycleSetup : nil
    }

    private enum Step: Hashable { case welcome, about, cycle, birthControl, pack, conditions, sleep, prefs }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .about: aboutStep
                case .cycle: cycleStep
                case .birthControl: birthControlStep
                case .pack: packStep
                case .conditions: conditionsStep
                case .sleep: sleepStep
                case .prefs: prefsStep
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Navigation

    private var usesBirthControl: Bool { store.data.cycleSetup == .hormonal }
    /// Pill, ring or patch: ask where she is in her pack.
    private var usesPack: Bool { store.birthControl?.hasBreakWeek == true }

    /// The steps she'll go through, from her answers so far. The birth
    /// control step stays in while she's on it, so the counter never repeats.
    private var flow: [Step] {
        var out: [Step] = [.about, .cycle]
        if usesBirthControl || step == .birthControl || step == .pack { out.append(.birthControl) }
        if usesPack || step == .pack { out.append(.pack) }
        out += [.conditions, .sleep, .prefs]
        return out
    }

    /// The counter treats "which birth control" and "your pack" as part of
    /// the cycle step, so picking birth control (or a pill instead of an
    /// implant) never changes the total mid-flow ("Step 2 of 5" stays "of 5").
    private var counted: [Step] { flow.filter { $0 != .birthControl && $0 != .pack } }

    private var totalSteps: Int { counted.count }

    private func number(of step: Step) -> Int {
        let s = (step == .pack || step == .birthControl) ? .cycle : step
        return (counted.firstIndex(of: s) ?? 0) + 1
    }

    private func go(_ next: Step) {
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    private func next() {
        let f = flow
        guard let i = f.firstIndex(of: step) else { go(.about); return }
        if i + 1 < f.count { go(f[i + 1]) }
    }

    private func back() {
        let f = flow
        guard let i = f.firstIndex(of: step), i > 0 else { go(.welcome); return }
        go(f[i - 1])
    }

    private func finish() {
        store.data.onboarded = true
        Task { await model.connectHealth() }
    }

    // MARK: Shared pieces

    private func topBar(trailing: (title: String, action: () -> Void)? = nil) -> some View {
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
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
            VStack(spacing: 6) {
                Text("Step\u{00A0}\(current)\u{00A0}of\u{00A0}\(totalSteps)")
                    .font(.scaled(size: 13, weight: .semibold))
                    .secondaryText()
                    .keepsOnOneLine()
                HStack(spacing: 4) {
                    ForEach(1...totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i <= current ? Accent.indigo.ink(scheme) : p.track)
                            .frame(width: 22, height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Spacer()
            if let trailing {
                Button(trailing.title, action: trailing.action)
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .keepsOnOneLine()
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.top, 8)
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

    private func privacyPill(_ text: String) -> some View {
        Label(text, systemImage: "lock.fill")
            .font(.scaled(size: 13, weight: .semibold))
            .foregroundStyle(Accent.mint.ink(scheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Accent.mint.tint(scheme), in: Capsule())
            .overlay(Capsule().strokeBorder(Accent.mint.fill(scheme).opacity(0.2)))
    }

    private func checkmark(_ on: Bool, size: CGFloat = 24) -> some View {
        ZStack {
            Circle().fill(on ? Accent.indigo.ink(scheme) : Color.clear)
            Circle().strokeBorder(on ? Color.clear : Palette(scheme: scheme).tertiary, lineWidth: 2)
            if on {
                Image(systemName: "checkmark")
                    .font(.scaled(size: size * 0.45, weight: .heavy))
                    .foregroundStyle(scheme == .dark ? Color(hex: 0x0E1136) : .white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Welcome

    private var welcome: some View {
        Screen(accent: .indigo) {
            ZStack {
                // Example numbers, labeled as such: nothing is hers yet.
                Ring(value: Double(model.recoveryShown ?? AppModel.recoveryAnchor) / 100, accent: .indigo, lineWidth: 16,
                     label: "\(model.recoveryShown ?? AppModel.recoveryAnchor)", caption: "Example", size: 180)
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
                go(.about)
            }
            .padding(.top, 8)
            Text("Apple Health asks about each kind of data. The app reads sleep, heart rate and HRV (how much the gap between heartbeats varies, a sign of how rested you are), steps and activity, daylight, wrist temperature, breathing rate, VO\u{2082} max (how fit your heart and lungs are), caffeine, water and cycle tracking. It only saves the caffeine and water you log here.")
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
                        Text("Your cycle data never leaves your phone.").font(.scaled(size: 14, weight: .bold))
                        Text("We can\u{2019}t see it, and neither can anyone else.").font(.scaled(size: 14)).secondaryText()
                    }
                }
                .accessibilityElement(children: .combine)
            }
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

    // MARK: About you

    private var nameBinding: Binding<String> {
        Binding(get: { store.data.name ?? "" },
                set: { store.data.name = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
    }

    private var ageBinding: Binding<Int> {
        Binding(get: { store.data.ageYears ?? 0 },
                set: { store.data.ageYears = $0 > 0 ? $0 : nil })
    }

    private var aboutStep: some View {
        let p = Palette(scheme: scheme)
        return Screen(accent: .purple) {
            topBar()
            heading("First,", "about you")
            intro("All optional, and it stays on your phone. Age and sex are used only for your fitness age.")
            Card(padding: 14) {
                AdaptiveStack(spacing: 4) {
                    Text("Name").font(.scaled(size: 15, weight: .bold))
                    TextField("Your first name", text: nameBinding)
                        .font(.scaled(size: 15))
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Your first name")
                }
                Divider().overlay(p.cardBorder)
                LabeledControlRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Age").font(.scaled(size: 15, weight: .bold))
                        Text("Compares your fitness with your own age group.").font(.scaled(size: 13)).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } control: {
                    Picker("Age", selection: ageBinding) {
                        Text("Skip").tag(0)
                        ForEach(13...90, id: \.self) { age in Text("\(age)").tag(age) }
                    }
                    .pickerStyle(.menu)
                    .tint(Accent.indigo.ink(scheme))
                    .fixedSize()
                }
                .frame(minHeight: 44)
            }
            PrimaryButton(title: "Continue") {
                nameFocused = false
                next()
            }
        }
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
                        dot: BodyLogStyle.phaseFill(.period, scheme)),
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
        Screen(accent: .purple) {
            topBar()
            heading("Tell us about", "your cycle")
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
        return usesBirthControl ? "Next: which birth control" : "Next: health conditions"
    }

    private func cycleCard(_ option: CycleOption) -> some View {
        let p = Palette(scheme: scheme)
        let on = cycleChoice == option.setup
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack(alignment: .bottomTrailing) {
        Button {
            var d = store.data
            d.cycleSetup = option.setup
            d.cycleSetupChosen = true
            store.data = d
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Circle().fill(option.dot).frame(width: 16, height: 16).padding(.top, 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title).font(.scaled(size: 16, weight: .bold))
                    Text(option.detail).font(.scaled(size: 14)).secondaryText()
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
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
            if option.setup == .irregular {
                InfoButton(title: "Irregular cycles and PCOS",
                           meaning: (ConditionCatalog.all.first { $0.name == "PCOS" }?.meaning ?? "") + " Irregular cycles can also come from stress, weight changes, the years after periods start, or for no clear reason.",
                           forYou: "Pick this if your cycle changes a lot from month to month or you have PCOS. The app counts days since your last period instead of predicting the next one. You can also add PCOS under Health conditions.")
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
        Screen(accent: .purple) {
            topBar()
            heading("Which", "birth control?")
            intro("Each one changes your body differently, so the app adjusts what it shows. Methods that stop ovulation never get ovulation or period predictions.")
            // One row when it fits; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ovulationLegend(.stops)
                    ovulationLegend(.may)
                    ovulationLegend(.natural)
                    InfoButton(topic: .ovulation).padding(.vertical, -12)
                }
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        ovulationLegend(.stops)
                        ovulationLegend(.may)
                        ovulationLegend(.natural)
                    }
                    InfoButton(topic: .ovulation)
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
        Screen(accent: .purple) {
            topBar(trailing: (title: "Skip", action: { next() }))
            heading("Where are you", "in your pack?")
            intro("Look at your pack: which \(packUnit) is today\u{2019}s? Then the break week and your withdrawal bleed land on the right days.")
            Card(padding: 14) {
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

    // MARK: Conditions

    private func toggleCondition(_ name: String) {
        if let i = store.data.conditions.firstIndex(of: name) {
            store.data.conditions.remove(at: i)
        } else {
            store.data.conditions.append(name)
        }
    }

    private var conditionsStep: some View {
        Screen(accent: .purple) {
            topBar(trailing: (title: "Skip", action: { next() }))
            heading("Any health", "conditions?")
            intro("Optional. Pick any that apply. Each one says exactly what it changes in the app. You can add or remove these anytime.")
            privacyPill("Private and stays on your phone")
            Card(padding: 12) {
                ForEach(Array(ConditionCatalog.all.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Palette(scheme: scheme).cardBorder) }
                    conditionRow(item)
                }
            }
            PrimaryButton(title: "Continue") { next() }
            Button {
                store.data.conditions = []
                next()
            } label: {
                Text("None of these")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private func conditionRow(_ item: ConditionCatalog.Item) -> some View {
        HStack(alignment: .top, spacing: 0) {
            conditionButton(item)
            InfoButton(title: item.name, meaning: item.meaning, forYou: "In this app: " + item.change)
                .padding(.vertical, -6)
        }
    }

    private func conditionButton(_ item: ConditionCatalog.Item) -> some View {
        let on = store.data.conditions.contains(item.name)
        return Button { toggleCondition(item.name) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.scaled(size: 22))
                    .foregroundStyle(on ? Accent.indigo.ink(scheme) : Palette(scheme: scheme).tertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.scaled(size: 15, weight: .bold))
                    Text(item.change).font(.scaled(size: 13)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Sleep

    private var sleepStep: some View {
        Screen(accent: .purple) {
            topBar()
            heading("Your", "sleep")
            intro("When do you usually go to bed, and what\u{2019}s the latest you can get up? Pick any times. These set your caffeine cutoff, wake plan and smart alarm. Change them anytime in Settings.")
            Card(padding: 14) {
                SleepScheduleControl()
            }
            SectionLabel(text: "Set up sleep tracking").padding(.top, 4)
            Card(padding: 14) {
                setupTip("bed.double.fill", .purple, "Turn on a sleep schedule or Sleep Focus",
                         "In the Health app, under Sleep. Apple Watch only tracks sleep when one is set up.")
                setupTip("applewatch", .indigo, "Wear your Watch to bed, snug",
                         "One finger\u{2019}s width above your wrist bone. A loose band misses heartbeats.")
                setupTip("battery.100.bolt", .mint, "Charge it before bed",
                         "Top it up while you shower or get ready, so it lasts the night.")
                setupTip("thermometer.medium", .coral, "Turn on Wrist Temperature",
                         "In the Watch app, under Health. It helps spot when you might be getting sick.")
                NavigationLink { AccuracyTipsView() } label: {
                    HStack(spacing: 6) {
                        Text("More ways to get accurate numbers")
                        Image(systemName: "chevron.right").font(.scaled(size: 12, weight: .bold)).accessibilityHidden(true)
                    }
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
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
                Text(title).font(.scaled(size: 15, weight: .bold))
                Text(why).font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Preferences

    private var caloriesBinding: Binding<Bool> {
        Binding(get: { store.data.showCalories && !model.caloriesHiddenByCondition },
                set: { store.data.showCalories = $0 })
    }

    private var caloriesDetail: String {
        model.caloriesHiddenByCondition
            ? "Off because you added an eating-disorder history."
            : "Off by default. No targets or food diary either way."
    }

    private var lightMode: Binding<Bool> {
        Binding(get: { appearance == "light" }, set: { appearance = $0 ? "light" : "dark" })
    }

    private var prefsStep: some View {
        Screen(accent: .purple) {
            topBar()
            heading("Make it", "yours")
            intro("Some things aren\u{2019}t helpful for everyone. Turn on only what you want to see.")
            Card(padding: 12) {
                SettingToggleRow(title: "Show calories", detail: caloriesDetail,
                                 systemImage: "flame.fill", accent: .orange, isOn: caloriesBinding)
                    .disabled(model.caloriesHiddenByCondition)
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                SettingToggleRow(title: "Sick alerts", detail: "A notification, at most once a day, when several overnight signals say you may be getting sick.",
                                 systemImage: "exclamationmark.triangle.fill", accent: .pink, isOn: $store.data.sickAlerts)
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                SettingToggleRow(title: "Peak and dip nudges", detail: "A notification 15 minutes before your energy peak and afternoon dip.",
                                 systemImage: "bolt.fill", accent: .yellow, isOn: $store.data.peakDipNudges)
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                SettingToggleRow(title: "Drinks tracking", detail: "See how alcohol affects your sleep and recovery.",
                                 systemImage: "wineglass.fill", accent: .purple, isOn: $store.data.drinksTracking)
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                SettingToggleRow(title: "Light mode", detail: "Dark is the default. Change it anytime in Settings.",
                                 systemImage: "sun.max.fill", accent: .yellow, isOn: lightMode)
            }
            // Optional: exams from her calendar, so exam weeks are planned for.
            CalendarImportCard()
            PrimaryButton(title: "Start learning my normal", action: finish)
            Text("Notifications ask for permission when you finish. Your own numbers replace the example ones after 14 nights.")
                .font(.scaled(size: 13))
                .secondaryText()
                .frame(maxWidth: .infinity)
        }
    }
}
