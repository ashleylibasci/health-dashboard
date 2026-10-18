import SwiftUI

/// First launch: say hi, set up the profile, bring in Health history and the calendar.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    enum Step: Int, CaseIterable { case intro, name, cycle, birthControl, prefs, health, calendar, done }

    @State private var step: Step = .intro
    @State private var name = ""
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -20, to: .now)!
    @State private var hasBirthday = false
    @State private var cycle: CycleMode?
    @State private var birthControl: BirthControl?
    @State private var conditions: Set<Condition> = []
    @State private var prefs = Preferences()
    @State private var calendarLink = ""
    @State private var bottleMl = 710.0
    @State private var connecting = false
    @State private var showConditions = false

    /// The steps actually shown, skipping birth control unless it applies.
    private var steps: [Step] {
        Step.allCases.filter { $0 != .birthControl || cycle == .hormonal }
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .intro && step != .done { progress.padding(.horizontal, 20).padding(.top, 12) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { page }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            footer.padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(step == .intro ? Color.lavender : Color.ground)
        .animation(.easeInOut(duration: 0.2), value: step)
        .sheet(isPresented: $showConditions) { conditionsSheet }
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch step {
        case .intro: intro
        case .name: namePage
        case .cycle: cyclePage
        case .birthControl: birthControlPage
        case .prefs: prefsPage
        case .health: healthPage
        case .calendar: calendarPage
        case .done: donePage
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack {
                Circle().stroke(Color.surface, lineWidth: 12).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: 0.72).stroke(Color.main, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 150, height: 150)
                Image(systemName: "moon.stars.fill").font(.system(size: 44)).foregroundStyle(Color.mainText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .accessibilityHidden(true)
            heading("Your body, explained. ", "Read from your Apple Watch.", size: 38)
            Text("Sleep, recovery, caffeine, your cycle and your exam weeks, read straight from Apple Health. Nothing to export.")
                .font(.system(size: 17)).foregroundStyle(Color(hex: 0x4A4F6E)).fixedSize(horizontal: false, vertical: true)
            privacyNote("Your health data stays on your phone. The app reads it here and never uploads it.")
        }
    }

    private var namePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Hi! ", "What’s your name?")
            Text("So the app knows what to call you.").font(.system(size: 15)).foregroundStyle(Color.muted)
            TextField("First name", text: $name)
                .font(.system(size: 22, weight: .semibold))
                .textContentType(.givenName)
                .submitLabel(.next)
                .padding(16)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.line))
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $hasBirthday) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add your birthday").font(.system(size: 15, weight: .bold))
                        Text("Used for fitness age: your heart fitness compared with people your age. Optional.")
                            .font(.system(size: 13)).foregroundStyle(Color.muted)
                    }
                }
                .tint(.main)
                if hasBirthday {
                    DatePicker("Birthday", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                        .font(.system(size: 15))
                }
            }
            .padding(16)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var cyclePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Tell us about ", "your cycle")
            Text("This changes what the app shows you. Every body is different, and you can change it anytime.")
                .font(.system(size: 15)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(CycleMode.allCases) { mode in
                choice(selected: cycle == mode, dot: dotColor(mode), title: mode.title, detail: mode.detail) { cycle = mode }
            }
            privacyNote("Stays on your phone. Never shared, never uploaded.")
        }
    }

    private var birthControlPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Which ", "birth control?")
            Text("Each one changes your body differently, so the app adjusts what it shows.")
                .font(.system(size: 15)).foregroundStyle(Color.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(BirthControl.allCases) { m in
                    Button { birthControl = m } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(m.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                            Text(m.note).font(.system(size: 12)).foregroundStyle(Color(hex: 0x4A4F6E))
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Pill(text: m.ovulationLabel, fill: tagFill(m), ink: tagInk(m))
                        }
                        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                        .padding(14)
                        .background(birthControl == m ? Color.lavender : Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(birthControl == m ? Color.mainText : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(birthControl == m ? .isSelected : [])
                }
            }
            Note("Not sure which pill you take? The name is on the pack, or ask your pharmacist. You can change this anytime.")
        }
    }

    private var prefsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Make it ", "yours")
            Text("Some things aren’t helpful for everyone. Turn on only what you want to see.")
                .font(.system(size: 15)).foregroundStyle(Color.muted)
            VStack(spacing: 0) {
                prefRow("Show calories", "Off by default. No targets or food diary either way.", $prefs.showCalories)
                Divider()
                prefRow("Body-working-harder alerts", "A heads-up when your signals look like a bug coming on.", $prefs.sickAlerts)
                Divider()
                prefRow("Drinks tracking", "See how alcohol affects your sleep and recovery.", $prefs.drinksTracking)
                Divider()
                prefRow("Streaks", "Small goals like brisk walks and bedtimes. Kept on your phone.", $prefs.streaks)
                Divider()
                prefRow("Dark Watch screens at night", "Switches automatically after sunset.", $prefs.darkWatchAtNight)
            }
            .padding(.horizontal, 18)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(alignment: .leading, spacing: 10) {
                Text("Your water bottle").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                Text("Log water in bottles (or a quarter or half of one) instead of glasses.").font(.system(size: 13)).foregroundStyle(Color.muted)
                FlowLayout {
                    ForEach(bottleSizes, id: \.ml) { b in
                        Chip(text: b.name, selected: bottleMl == b.ml) { bottleMl = b.ml }
                    }
                }
            }
            .padding(16)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button { showConditions = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conditions.isEmpty ? "Add a health condition" : conditions.map(\.name).sorted().joined(separator: ", "))
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                        Text("PCOS, endometriosis, thyroid and more. Optional.").font(.system(size: 13)).foregroundStyle(Color(hex: 0x4A4F6E))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.mainText)
                }
                .padding(16)
                .background(Color.lavender, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var healthPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Bring in your ", "health history")
            Text("Connect Apple Health and the app reads everything your iPhone and Watch have already recorded: years of sleep, heart rate, workouts, cycle and drinks. Nothing to export or upload.")
                .font(.system(size: 15)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            Card(fill: .lavender) {
                switch model.healthState {
                case .ready:
                    Label("Connected", systemImage: "checkmark.circle.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(Color.mintInk)
                    Text(importSummary).font(.system(size: 15)).foregroundStyle(Color.ink)
                case .loading:
                    ProgressView("Reading your history…")
                case .failed(let message):
                    Note("Couldn’t read Apple Health: \(message)")
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Tap **Select All**, then **Continue**.")
                        step(2, "When Apple asks how much data to share, pick **All Recorded Data and Future Data**. That’s what brings in your history.")
                        step(3, "Tap **Allow**. You can change this later in the Settings app → Health.")
                    }
                }
            }
            privacyNote("Read on your phone, never uploaded. The app can also save what you log in it, like a latte or a period day.")
        }
    }

    private var importSummary: String {
        let h = model.health
        guard let first = h.nights.first?.date else { return "No sleep found yet. It fills in as you wear your Watch to bed." }
        return "Found \(h.nights.count) nights of sleep since \(Day.short(first)), \(h.restingHr.count) days of heart data and \(h.caffeine.count) caffeine logs."
    }

    private var calendarPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Connect ", "Google Calendar")
            Text("The app looks for exams, midterms, finals and quizzes so it can warn you before exam week and compare how you sleep then.")
                .font(.system(size: 15)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                step(1, "On a computer, open **calendar.google.com** → the gear → **Settings**.")
                step(2, "Click the calendar your exams are in, then copy **Secret address in iCal format**.")
                step(3, "Send it to your phone (AirDrop or Notes) and paste it below.")
            }
            .padding(16)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            SecureField("Paste the secret address", text: $calendarLink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(16)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.line))
            if case .failed(let message) = model.calendarState { Note(message) }
            if case .ready = model.calendarState, model.calendarURL != nil {
                Label("Connected: \(model.exams.count) exams found", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.mintInk)
            }
            privacyNote("Treat the link like a password: anyone with it can read that calendar. It’s kept in your phone’s Keychain.")
        }
    }

    private var donePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sun.horizon.fill").font(.system(size: 56)).foregroundStyle(Color.main)
                .frame(maxWidth: .infinity).padding(.top, 48).accessibilityHidden(true)
            heading("You’re all set, ", "\(trimmedName).")
            Text("Scores like recovery and sleep regularity fill in over your first 14 days as the app learns your normal. Everything can be changed later from the circle with your initial on the Today screen.")
                .font(.system(size: 16)).foregroundStyle(Color(hex: 0x4A4F6E)).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: next) {
                Group {
                    if connecting { ProgressView().tint(.white) } else { Text(primaryLabel) }
                }
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(.white)
                .background(canContinue ? Color.ink : Color.muted.opacity(0.5), in: Capsule())
            }
            .disabled(!canContinue || connecting)
            HStack {
                if step != .intro && step != .done {
                    Button("Back", action: back).font(.system(size: 15, weight: .semibold)).frame(minHeight: 44)
                }
                Spacer()
                if let skip = skipLabel {
                    Button(skip, action: advance).font(.system(size: 15, weight: .semibold)).frame(minHeight: 44)
                }
            }
            .foregroundStyle(Color.mainText)
        }
    }

    private var primaryLabel: String {
        switch step {
        case .intro: "Get started"
        case .health: model.healthState == .ready ? "Continue" : "Connect Apple Health"
        case .calendar: calendarLink.trimmingCharacters(in: .whitespaces).isEmpty || model.calendarURL != nil ? "Continue" : "Connect calendar"
        case .done: "Start learning my normal"
        default: "Continue"
        }
    }

    private var skipLabel: String? {
        switch step {
        case .health: model.healthState == .ready ? nil : "Skip for now"
        case .calendar: "Skip for now"
        default: nil
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canContinue: Bool {
        switch step {
        case .name: !trimmedName.isEmpty
        case .cycle: cycle != nil
        case .birthControl: birthControl != nil
        default: true
        }
    }

    private func next() {
        switch step {
        case .health where model.healthState != .ready:
            connecting = true
            Task {
                await model.connectHealth()
                connecting = false
            }
        case .calendar where !calendarLink.trimmingCharacters(in: .whitespaces).isEmpty && model.calendarURL == nil:
            connecting = true
            Task {
                await model.setCalendarURL(calendarLink)
                connecting = false
                if case .ready = model.calendarState { advance() }
            }
        case .done:
            model.profile = Profile(
                name: trimmedName,
                birthday: hasBirthday ? birthday : nil,
                cycle: cycle ?? .notTracking,
                birthControl: cycle == .hormonal ? birthControl : nil,
                conditions: conditions,
                prefs: prefs,
                bottleMl: bottleMl
            )
        default:
            advance()
        }
    }

    private func advance() {
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return }
        step = steps[i + 1]
    }

    private func back() {
        guard let i = steps.firstIndex(of: step), i > 0 else { return }
        step = steps[i - 1]
    }

    // MARK: Pieces

    private var progress: some View {
        let shown = steps.filter { $0 != .intro && $0 != .done }
        let index = shown.firstIndex(of: step) ?? 0
        return HStack(spacing: 6) {
            ForEach(shown.indices, id: \.self) { i in
                Capsule().fill(i <= index ? Color.main : Color(hex: 0xE4E7FF)).frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(shown.count)")
    }

    private func heading(_ plain: String, _ accent: String, size: CGFloat = 32) -> some View {
        (Text(plain) + Text(accent).italic().foregroundColor(.mainText))
            .font(.serifTitle(size)).foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func privacyNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Color.mainText)
            Text(text).font(.system(size: 13)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice(selected: Bool, dot: Color, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Circle().fill(dot).frame(width: 16, height: 16).padding(.top, 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                    Text(detail).font(.system(size: 14)).foregroundStyle(Color(hex: 0x4A4F6E))
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(selected ? Color.lavender : Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? Color.mainText : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func prefRow(_ title: String, _ detail: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.ink)
                Text(detail).font(.system(size: 13)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.main)
        .padding(.vertical, 12)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.mainText)
                .frame(width: 24, height: 24).background(Color.lavender, in: Circle())
            Text(text).font(.system(size: 14)).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var conditionsSheet: some View {
        NavigationStack {
            List(Condition.allCases) { c in
                Button {
                    if conditions.contains(c) { conditions.remove(c) } else { conditions.insert(c) }
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.headline).foregroundStyle(Color.ink)
                            Text(c.detail).font(.subheadline).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        if conditions.contains(c) { Image(systemName: "checkmark").foregroundStyle(Color.mainText).fontWeight(.bold) }
                    }
                }
                .accessibilityAddTraits(conditions.contains(c) ? .isSelected : [])
            }
            .navigationTitle("Health conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showConditions = false } } }
        }
    }

    private func dotColor(_ mode: CycleMode) -> Color {
        switch mode {
        case .natural: Color(hex: 0xF07A6B)
        case .hormonal: .main
        case .irregular: Color(hex: 0xFFD2BD)
        case .notTracking: Color(hex: 0xD5D7E3)
        }
    }

    private func tagFill(_ m: BirthControl) -> Color {
        switch m.ovulation { case .natural: .mint; case .stops: Color(hex: 0xE4E7FF); default: .butter }
    }

    private func tagInk(_ m: BirthControl) -> Color {
        switch m.ovulation { case .natural: .mintInk; case .stops: .mainText; default: .butterInk }
    }
}
