import SwiftUI

/// First launch: say hi, set up the profile, bring in Health history and the calendar.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    /// Health comes before the personal questions, so people see their own numbers first.
    enum Step: Int, CaseIterable { case intro, name, health, cycle, birthControl, prefs, calendar, reminders, done }

    @State private var step: Step = OnboardingView.startStep

    /// Test builds can open a step directly with `-step reminders` (etc.).
    private static var startStep: Step {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-step"), i + 1 < args.count,
           let match = Step.allCases.first(where: { "\($0)" == args[i + 1] }) { return match }
        #endif
        return .intro
    }
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
    @State private var showLinkField = false
    @State private var calendarChoice: AppModel.CalendarSource = .google

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
            // The footer stays put while the page scrolls, so it grows less to leave room for the page.
            footer.padding(.horizontal, 20).padding(.bottom, 12)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .background(step == .intro ? Color.lavender : Color.ground)
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear(perform: prefill)
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
        case .reminders: remindersPage
        case .done: donePage
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack {
                Circle().stroke(Color.surface, lineWidth: 12).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: 0.72).stroke(Color.main, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 150, height: 150)
                Image(systemName: "moon.stars.fill").scaledFont(44).foregroundStyle(Color.mainText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .accessibilityHidden(true)
            heading("Your body, explained. ", "Read from your Apple Watch.", size: 38)
            Text("Sleep, recovery, caffeine, your cycle and your exam weeks, read straight from Apple Health. Nothing to export.")
                .scaledFont(17).foregroundStyle(Color.muted2).fixedSize(horizontal: false, vertical: true)
            privacyNote("Your health data stays on your phone. The app reads it here and never uploads it.")
        }
    }

    private var namePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Hi! ", "What’s your name?")
            Text("So the app knows what to call you.").scaledFont(15).foregroundStyle(Color.muted)
            TextField("First name", text: $name)
                .scaledFont(22, .semibold)
                .textContentType(.givenName)
                .submitLabel(.next)
                .padding(16)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.line))
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $hasBirthday) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add your birthday").scaledFont(15, .bold)
                        Text("Used for fitness age: your heart fitness compared with people your age. Optional.")
                            .scaledFont(13).foregroundStyle(Color.muted)
                    }
                }
                .tint(.main)
                if hasBirthday {
                    DatePicker("Birthday", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                        .scaledFont(15)
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
                .scaledFont(15).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
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
                .scaledFont(15).foregroundStyle(Color.muted)
            AdaptiveGrid(columns: 2, spacing: 10) {
                ForEach(BirthControl.allCases) { m in
                    Button { birthControl = m } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(m.name).scaledFont(15, .bold).foregroundStyle(Color.ink)
                            Text(m.note).scaledFont(12).foregroundStyle(Color.muted2)
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
                .scaledFont(15).foregroundStyle(Color.muted)
            VStack(spacing: 0) {
                prefRow("Show calories", "Off by default. No targets or food diary either way.", $prefs.showCalories)
                Divider()
                prefRow("Body-working-harder alerts", "A heads-up when your signals look like a bug coming on.", $prefs.sickAlerts)
                Divider()
                prefRow("Drinks tracking", "See how alcohol affects your sleep and recovery.", $prefs.drinksTracking)
                Divider()
                prefRow("Streaks", "Small goals like brisk walks and bedtimes. Kept on your phone.", $prefs.streaks)
            }
            .padding(.horizontal, 18)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(alignment: .leading, spacing: 10) {
                Text("Your water bottle").scaledFont(15, .bold).foregroundStyle(Color.ink)
                Text("Log water in bottles (or a quarter or half of one) instead of glasses.").scaledFont(13).foregroundStyle(Color.muted)
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
                            .scaledFont(15, .bold).foregroundStyle(Color.ink)
                        Text("PCOS, endometriosis, thyroid and more. Optional.").scaledFont(13).foregroundStyle(Color.muted2)
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
            Text("Connect Apple Health and the app reads everything your iPhone and Watch have already recorded: the past year of sleep, heart rate, workouts, cycle and drinks. Nothing to export or upload.")
                .scaledFont(15).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            Card(fill: .lavender) {
                switch model.healthState {
                case .ready:
                    Label("Connected", systemImage: "checkmark.circle.fill").scaledFont(17, .bold).foregroundStyle(Color.mintInk)
                    Text(importSummary).scaledFont(15).foregroundStyle(Color.ink)
                    if model.historyLooksShort { ShortHistoryNote() }
                case .loading:
                    ProgressView("Reading your history…")
                case .failed(let message):
                    Note("Couldn’t read Apple Health: \(message)")
                default:
                    Text("Apple shows two screens. Turn everything on, and on the second one pick this:")
                        .scaledFont(15).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                    AppleSheetPicture()
                }
            }
            privacyNote("Read on your phone, never uploaded. The app can also save what you log in it, like a latte or a period day.")
        }
    }

    private var importSummary: String {
        let h = model.health
        guard let first = h.nights.first?.date else {
            // Apple doesn't tell apps when access was refused, so nothing at all usually means that.
            if h.restingHr.isEmpty && h.steps.isEmpty {
                return "Nothing came in. If you tapped Don’t Allow or turned items off, turn them on in the Settings app → Health → Data Access & Devices → Health Dashboard. If your Watch is new, it fills in as you wear it."
            }
            return "No sleep found yet. It fills in as you wear your Watch to bed."
        }
        return "Found \(h.nights.count) nights of sleep since \(Day.short(first)), \(h.restingHr.count) days of heart data and \(h.caffeine.count) caffeine logs."
    }

    private var calendarPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Connect your ", "calendar")
            Text("The app looks for exams, midterms, finals and quizzes so it can warn you before exam week and compare how you sleep then.")
                .font(.subheadline).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            if model.isCalendarConnected, case .ready = model.calendarState {
                Card(fill: .mint) {
                    Label("\(sourceName(model.calendarSource)) connected: \(model.exams.count) exam\(model.exams.count == 1 ? "" : "s") found", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(Color.mintInk)
                }
            } else if model.isCalendarConnected {
                // Connected, but the first read is still going or didn't work: offer retry or a different choice.
                Card(fill: .lavender) {
                    if case .loading = model.calendarState {
                        ProgressView("Reading \(sourceName(model.calendarSource))…")
                    } else {
                        Label("\(sourceName(model.calendarSource)) is connected, but it couldn’t be read yet.", systemImage: "exclamationmark.circle")
                            .font(.headline).foregroundStyle(Color.ink)
                    }
                    HStack {
                        Button("Try again") { Task { await model.refreshCalendar(force: true) } }.fontWeight(.bold)
                        Spacer()
                        Button("Choose a different one") { Task { await model.disconnectCalendar() } }
                    }
                    .font(.subheadline)
                }
            } else {
                CalendarChoiceCard(
                    selected: calendarChoice == .google, icon: "g.circle.fill", title: "Google Calendar",
                    detail: model.googleConfigured ? "Sign in with Google. The app reads your calendar straight from Google, read-only."
                        : "Needs a one-time setup on a computer first. Until then, use Apple Calendar or a link.",
                    enabled: model.googleConfigured
                ) { calendarChoice = .google; showLinkField = false }
                CalendarChoiceCard(
                    selected: calendarChoice == .apple, icon: "calendar", title: "Apple Calendar",
                    detail: "Reads the calendars on this iPhone, including any accounts added in Settings → Calendar → Accounts.",
                    enabled: true
                ) { calendarChoice = .apple; showLinkField = false }
                Button(showLinkField ? "Hide the link option" : "Can’t sign in? Use a Google secret link instead") {
                    showLinkField.toggle()
                    calendarChoice = showLinkField ? .link : (model.googleConfigured ? .google : .apple)
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.mainText)
                if showLinkField {
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "On a computer, open **calendar.google.com** → the gear → **Settings**.")
                        step(2, "Click the calendar your exams are in, then copy **Secret address in iCal format**.")
                        step(3, "Send it to your phone and paste it below. Treat it like a password.")
                    }
                    .padding(16)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    SecureField("Paste the secret address", text: $calendarLink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(16)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.line))
                }
            }
            if case .failed(let message) = model.calendarState { Note(message) }
            privacyNote("Read-only. Events are read on your phone and never uploaded.")
        }
        .onAppear { if !model.googleConfigured { calendarChoice = .apple } }
    }

    private func sourceName(_ source: AppModel.CalendarSource?) -> String {
        switch source { case .google?: "Google Calendar"; case .apple?: "Apple Calendar"; case .link?: "Calendar link"; case nil: "Calendar" }
    }

    private var remindersPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Want a ", "heads-up?")
            Text("Two kinds of reminders, and only these. No streak nagging, no daily pings.")
                .scaledFont(15).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                reminderRow("calendar", .butter, .butterInk, "The night before an exam", "“Midterm tomorrow. Aim to be asleep by 12:15.” Sent at 9pm.")
                reminderRow("thermometer.medium", .peach, .peachInk, "When your body’s working harder", "If several signals move together, like before a cold. Turn off anytime in Settings.")
            }
            if let allowed = model.notificationsAllowed {
                Label(allowed ? "Reminders are on" : "Reminders are off. You can turn them on later in Settings.", systemImage: allowed ? "checkmark.circle.fill" : "bell.slash")
                    .scaledFont(15, .bold).foregroundStyle(allowed ? Color.mintInk : Color.muted)
            }
            privacyNote("Reminders are made on your phone; nothing is sent to a server.")
        }
    }

    private func reminderRow(_ icon: String, _ fill: Color, _ ink: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 0) {
            AdaptiveStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).scaledFont(18).foregroundStyle(ink).limitedTextGrowth()
                    .frame(width: 40, height: 40).background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).scaledFont(15, .bold).foregroundStyle(Color.ink)
                    Text(detail).scaledFont(13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var donePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sun.horizon.fill").scaledFont(56).foregroundStyle(Color.main)
                .frame(maxWidth: .infinity).padding(.top, 48).accessibilityHidden(true)
            heading(trimmedName.isEmpty ? "You’re " : "You’re all set, ", trimmedName.isEmpty ? "all set." : "\(trimmedName).")
            if let r = model.recoveryToday {
                AdaptiveStack(spacing: 16) {
                    Ring(value: r.score, size: 88)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery today: \(r.label)").numberFont(20).foregroundStyle(Color.ink)
                        Text(r.reason).scaledFont(14).foregroundStyle(Color.muted2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .background(Color.lavender, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                Text("Your history came in, so your scores are ready now: \(importSummary.prefix(1).lowercased() + importSummary.dropFirst())")
                    .scaledFont(16).foregroundStyle(Color.muted2).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Scores like recovery and sleep regularity fill in over your first two weeks as your Watch records nights. Everything can be changed later from the circle with your initial on the Today screen.")
                    .scaledFont(16).foregroundStyle(Color.muted2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: next) {
                Group {
                    if connecting { ProgressView().tint(Color.onSolid) } else { Text(primaryLabel) }
                }
                .scaledFont(18, .bold, design: .rounded)
                .multilineTextAlignment(.center).padding(.horizontal, 20).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(Color.onSolid)
                .background(canContinue ? Color.solid : Color.muted.opacity(0.5), in: Capsule())
            }
            .disabled(!canContinue || connecting)
            HStack {
                if step != .intro && step != .done {
                    Button("Back", action: back).scaledFont(15, .semibold).frame(minHeight: 44)
                }
                Spacer()
                if let skip = skipLabel {
                    Button(skip, action: advance).scaledFont(15, .semibold).frame(minHeight: 44)
                }
            }
            .foregroundStyle(Color.mainText)
        }
    }

    private var primaryLabel: String {
        switch step {
        case .intro: "Get started"
        case .health: model.healthState == .ready ? "Continue" : "Connect Apple Health"
        case .calendar:
            model.isCalendarConnected ? "Continue"
                : calendarChoice == .google ? "Sign in with Google"
                : calendarChoice == .apple ? "Use Apple Calendar" : "Connect with link"
        case .reminders: model.notificationsAllowed == nil ? "Turn on reminders" : "Continue"
        case .done: model.recoveryToday == nil ? "Start learning my normal" : "See today"
        default: "Continue"
        }
    }

    private var skipLabel: String? {
        switch step {
        case .health: model.healthState == .ready ? nil : "Skip for now"
        case .calendar: model.isCalendarConnected ? nil : "Skip for now"
        case .reminders: model.notificationsAllowed == nil ? "Not now" : nil
        default: nil
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canContinue: Bool {
        switch step {
        case .name: !trimmedName.isEmpty
        case .cycle: cycle != nil
        case .birthControl: birthControl != nil
        case .calendar: model.isCalendarConnected
            || (calendarChoice == .google && model.googleConfigured)
            || calendarChoice == .apple
            || (calendarChoice == .link && !calendarLink.trimmingCharacters(in: .whitespaces).isEmpty)
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
        case .calendar where !model.isCalendarConnected:
            connecting = true
            Task {
                switch calendarChoice {
                case .google: await model.connectGoogle()
                case .apple: await model.connectDeviceCalendar()
                case .link: await model.setCalendarURL(calendarLink)
                }
                connecting = false
            }
        case .reminders where model.notificationsAllowed == nil:
            Task { await model.requestNotifications() }
        case .done:
            var profile = Profile(
                name: trimmedName,
                birthday: hasBirthday ? birthday : nil,
                cycle: cycle ?? .notTracking,
                birthControl: cycle == .hormonal ? birthControl : nil,
                conditions: conditions,
                prefs: prefs,
                packStart: model.previousProfile?.packStart,
                bottleMl: bottleMl
            )
            profile.pillsTaken = model.previousProfile?.pillsTaken ?? []
            model.previousProfile = nil
            model.profile = profile
        default:
            advance()
        }
    }

    /// Running the welcome screens again starts with the current answers filled in.
    private func prefill() {
        guard let p = model.previousProfile, name.isEmpty else { return }
        name = p.name
        if let b = p.birthday { birthday = b; hasBirthday = true }
        cycle = p.cycle
        birthControl = p.birthControl
        conditions = p.conditions
        prefs = p.prefs
        bottleMl = p.bottleMl
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
                Capsule().fill(i <= index ? Color.main : Color.periwinkle).frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(shown.count)")
    }

    private func heading(_ plain: String, _ accent: String, size: CGFloat = 32) -> some View {
        (Text(plain) + Text(accent).italic().foregroundColor(.mainText))
            .serifTitleFont(size).foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func privacyNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Color.mainText)
            Text(text).scaledFont(13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice(selected: Bool, dot: Color, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Circle().fill(dot).frame(width: 16, height: 16).padding(.top, 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).scaledFont(16, .bold).foregroundStyle(Color.ink)
                    Text(detail).scaledFont(14).foregroundStyle(Color.muted2)
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
                Text(title).scaledFont(15, .bold).foregroundStyle(Color.ink)
                Text(detail).scaledFont(13).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.main)
        .padding(.vertical, 12)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").scaledFont(13, .bold).foregroundStyle(Color.mainText).limitedTextGrowth()
                .frame(width: 24, height: 24).background(Color.lavender, in: Circle())
            Text(text).scaledFont(14).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
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
        switch m.ovulation { case .natural: .mint; case .stops: Color.periwinkle; default: .butter }
    }

    private func tagInk(_ m: BirthControl) -> Color {
        switch m.ovulation { case .natural: .mintInk; case .stops: .mainText; default: .butterInk }
    }
}

/// A drawing of Apple's "How much data" sheet with the right choice circled.
struct AppleSheetPicture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How much data would you like to share?").scaledFont(13, .bold).foregroundStyle(Color.ink)
            option("Past 30 Days and Future Data", picked: false)
            option("All Recorded Data and Future Data", picked: true)
            HStack(spacing: 6) {
                Image(systemName: "hand.point.up.left.fill").foregroundStyle(Color.mainText)
                Text("Pick this one, then tap Allow").scaledFont(12, .bold).foregroundStyle(Color.mainText)
            }
            .padding(.leading, 4)
        }
        .padding(12)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("On Apple’s screen asking how much data to share, choose All Recorded Data and Future Data, then tap Allow.")
    }

    private func option(_ text: String, picked: Bool) -> some View {
        Text(text).scaledFont(13, picked ? .bold : .regular).foregroundStyle(picked ? Color.ink : Color.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.track, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(picked ? Color.mainText : .clear, lineWidth: 2.5))
    }
}

/// Shown when only about a month of Health data came in.
struct ShortHistoryNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Only about a month came in", systemImage: "exclamationmark.triangle.fill").scaledFont(15, .bold).foregroundStyle(Color.peachInk)
            Text("If your Watch is newer than a month, that’s all there is, and you can ignore this. If you’ve had it longer, Apple’s screen was probably set to “Past 30 Days.” To bring in the rest, open the Settings app → Health → Data Access & Devices → Health Dashboard and look for the option to share all past data.")
                .scaledFont(14).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.peach, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One calendar option on the welcome step.
struct CalendarChoiceCard: View {
    var selected: Bool
    var icon: String
    var title: String
    var detail: String
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.title2).foregroundStyle(Color.mainText)
                    .frame(width: 40, height: 40).background(Color.lavender, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color.ink)
                    Text(detail).font(.subheadline).foregroundStyle(Color.muted2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? Color.mainText : Color.muted)
            }
            .padding(16)
            .background(selected ? Color.lavender : Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? Color.mainText : .clear, lineWidth: 2))
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
