import SwiftUI
import HealthCore

/// One search across the app (D-S1): screens, settings pages and Health
/// guide articles. Pull down on any tab for the search field; a result
/// opens on that tab's stack (or switches tab), like any other link.
struct SearchItem: Identifiable, Hashable {
    enum Kind: Hashable { case screen, setting, article }
    enum Target: Hashable {
        case tab(AppTab)
        case screen(SearchScreen)
        case article(GuideArticle)
    }

    var id: String
    var kind: Kind
    var title: String
    var note: String
    var systemImage: String
    var accent: Accent
    /// Extra words she might type ("Google Calendar", "bedtime").
    var keywords: [String] = []
    var target: Target

    /// Every word of the query is in the title, note or keywords; guide
    /// articles also match their body.
    func matches(_ query: String) -> Bool {
        if case .article(let article) = target { return article.matches(query) }
        let text = ([title, note] + keywords).joined(separator: " ")
        return query.split(separator: " ").allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    /// Title matches first, then everything else, so "pill" finds the pill
    /// screens before every article that mentions a pill.
    func rank(_ query: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespaces)
        if title.localizedCaseInsensitiveCompare(q) == .orderedSame { return 0 }
        if title.localizedCaseInsensitiveContains(q) { return 1 }
        if keywords.contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return 2 }
        return 3
    }
}

/// The screens and settings pages search can open (tab roots switch tab
/// instead).
enum SearchScreen: Hashable {
    case recovery, hrv, restingHR, stress, checkIn, whyOff
    case sleepStages, sleepHistory, sleepNeed, wakePlan, learning, lateNights, timeChange, accuracy
    case energy, weekRecap, streaks, exams
    case cycle, cycleLog, cyclePhases, birthControl, visitSummary, pcos
    case sick, fitness, bodyClock, calories
    case caffeine, cutoffTest, water, drinks
    case settings, profile, conditions, calendars, cycleSettings, sleepSettings, tracking
    case notifications, widgetsWatch, healthData, appearance

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .recovery: RecoveryView()
        case .hrv: HeartMetricView(metric: .hrv)
        case .restingHR: HeartMetricView(metric: .restingHR)
        case .stress: StressView()
        case .checkIn: CheckInView()
        case .whyOff: WhyOffView()
        case .sleepStages: SleepStagesView()
        case .sleepHistory: SleepHistoryView()
        case .sleepNeed: SleepNeedView()
        case .wakePlan: WakePlanView()
        case .learning: LearningView()
        case .lateNights: LateNightView()
        case .timeChange: TimeChangeView()
        case .accuracy: AccuracyTipsView()
        case .energy: EnergyView()
        case .weekRecap: WeekRecapView()
        case .streaks: AchievementsView()
        case .exams: ExamListView()
        case .cycle: CycleView()
        case .cycleLog: CycleLogView()
        case .cyclePhases: CyclePhasesView()
        case .birthControl: BirthControlLearnView()
        case .visitSummary: VisitSummaryView()
        case .pcos: PCOSView()
        case .sick: SickView()
        case .fitness: FitnessView()
        case .bodyClock: ChronotypeView()
        case .calories: CaloriesView()
        case .caffeine: CaffeineView()
        case .cutoffTest: CutoffTestView()
        case .water: WaterView()
        case .drinks: DrinksView()
        case .settings: SettingsView()
        case .profile: ProfileSettingsView()
        case .conditions: ConditionsView()
        case .calendars: CalendarSettingsView()
        case .cycleSettings: CycleSettingsView()
        case .sleepSettings: SleepSettingsView()
        case .tracking: TrackingSettingsView()
        case .notifications: NotificationSettingsView()
        case .widgetsWatch: WidgetsWatchSettingsView()
        case .healthData: DataSettingsView()
        case .appearance: AppearanceSettingsView()
        }
    }
}

/// What search looks through, built for her setup (no cycle screens when
/// she isn't tracking, no alcohol when it's off, birth-control articles
/// for her method only).
@MainActor
enum AppSearch {
    static func items(model: AppModel, store: DataStore) -> [SearchItem] {
        let data = store.data
        let tracksCycle = data.cycleSetup != .notTracking
        let onBirthControl = data.cycleSetup == .hormonal
        let onPack = store.birthControl?.hasBreakWeek == true

        func screen(_ s: SearchScreen, _ title: String, _ note: String, _ image: String, _ accent: Accent,
                    _ keywords: [String] = [], setting: Bool = false) -> SearchItem {
            SearchItem(id: "\(s)", kind: setting ? .setting : .screen, title: title, note: note,
                       systemImage: image, accent: accent, keywords: keywords, target: .screen(s))
        }
        func tab(_ t: AppTab, _ title: String, _ note: String, _ image: String, _ keywords: [String]) -> SearchItem {
            SearchItem(id: "tab.\(t)", kind: .screen, title: title, note: note, systemImage: image,
                       accent: .indigo, keywords: keywords, target: .tab(t))
        }

        var out: [SearchItem] = [
            tab(.today, "Today", "Tab", "house.fill", ["home", "at a glance", "tonight"]),
            tab(.sleep, "Sleep", "Tab", "moon.fill", ["last night", "best bedtime"]),
            tab(.body, "Body", "Tab", "heart.fill", ["vitals", "rhythms"]),
            tab(.log, "Log", "Tab", "plus", ["log", "add", "latte", "coffee", "bottle", "flow"]),

            screen(.recovery, "Recovery", "Today", "bolt.heart.fill", .mint, ["readiness", "score"]),
            screen(.hrv, "HRV", "Heart rate variability", "waveform.path.ecg", .indigo, ["heart rate variability", "variability"]),
            screen(.restingHR, "Resting heart rate", "Body \u{00B7} Vitals", "heart.fill", .pink, ["RHR", "pulse", "bpm"]),
            screen(.stress, "Stress", "Today", "waveform.path", .orange, ["mood", "anxiety", "calm"]),
            screen(.checkIn, "Morning check-in", "How you feel this morning", "sun.max.fill", .orange, ["feel", "mood", "rested"]),
            screen(.whyOff, "Why do I feel off?", "Your likeliest reasons today", "questionmark.circle.fill", .coral, ["tired", "off", "low"]),
            screen(.sleepStages, "Sleep stages", "Sleep \u{00B7} last night", "chart.bar.fill", .purple, ["deep", "REM", "core", "awake"]),
            screen(.sleepHistory, "Sleep history", "Sleep \u{00B7} past nights", "calendar", .purple, ["nights", "past", "trend"]),
            screen(.sleepNeed, "Sleep need and debt", "Sleep", "bed.double.fill", .purple, ["debt", "how much sleep", "need"]),
            screen(.wakePlan, "Wake plan and smart alarm", "Sleep", "alarm.fill", .purple, ["alarm", "wake", "Watch alarm", "smart alarm", "up by"]),
            screen(.learning, "Learning you", "What the app knows so far", "sparkles", .purple, ["nights", "learning"]),
            screen(.lateNights, "Late nights", "Sleep", "moon.stars.fill", .purple, ["all-nighter", "stayed up", "cushion"]),
            screen(.timeChange, "Time change", "Clocks going back or forward", "clock.arrow.circlepath", .purple, ["daylight saving", "DST", "jet lag"]),
            screen(.accuracy, "Getting accurate numbers", "Checklist", "checklist", .indigo, ["accuracy", "Watch", "setup", "tips"]),
            screen(.energy, "Energy", "Body \u{00B7} your curve today", "bolt.fill", .mint, ["energy curve", "focus", "peak", "dip", "energy left"]),
            screen(.weekRecap, "Your week", "Last week at a glance", "calendar.badge.clock", .indigo, ["recap", "week", "summary"]),
            screen(.streaks, "Streaks", "Bedtime and logging streaks", "flame.fill", .yellow, ["achievements", "streak"]),
            screen(.exams, "Exams", "Exam list and exam mode", "graduationcap.fill", .yellow, ["exam", "test", "finals", "calendar", "study"]),
            screen(.sick, "Sick check", "Body \u{00B7} Vitals", "thermometer.medium", .coral, ["ill", "sick", "temperature", "breathing rate", "cold", "flu"]),
            screen(.fitness, "Fitness", "Body \u{00B7} VO\u{2082} max", "figure.run", .mint, ["VO2 max", "cardio", "fitness age"]),
            screen(.bodyClock, "Body clock", "Body \u{00B7} chronotype", "sun.and.horizon.fill", .purple, ["chronotype", "night owl", "early bird", "daylight"]),
            screen(.caffeine, "Caffeine", "Log \u{00B7} history and cutoff", "cup.and.saucer.fill", .yellow, ["coffee", "latte", "tea", "cutoff", "energy drink"]),
            screen(.cutoffTest, "Caffeine cutoff test", "Caffeine", "flask.fill", .yellow, ["cutoff", "experiment"]),
            screen(.water, "Water", "Log \u{00B7} today and goal", "drop.fill", .blue, ["hydration", "bottle", "drink water", "oz"]),
        ]
        if tracksCycle {
            out += [
                screen(.cycle, onPack ? "Pill pack" : "Cycle", "Body \u{00B7} Rhythms", onPack ? "pills.fill" : "drop.fill", .pink,
                       ["period", "cycle", "pill", "pack", "break week", "bleed", "ovulation"]),
                screen(.cycleLog, "Period and symptom log", "Past days to edit", "list.bullet", .pink, ["period", "flow", "bleeding", "symptoms", "cramps", "spotting"]),
                screen(.cyclePhases, "How your cycle affects you", "Cycle", "circle.dashed", .pink, ["phases", "luteal", "follicular", "PMS"]),
            ]
        }
        if onBirthControl {
            out.append(screen(.birthControl, "How your birth control works", "Cycle", "pills.fill", .indigo, ["pill", "birth control", "contraception", "IUD"]))
        }
        if onPack {
            out.append(screen(.visitSummary, "Pill visit summary", "One page for a visit", "doc.text.fill", .pink, ["PDF", "export", "doctor", "appointment", "pill"]))
        }
        if data.conditions.contains("PCOS") {
            out.append(screen(.pcos, "PCOS", "Health condition", "heart.text.square.fill", .pink, ["polycystic"]))
        }
        if model.showsCalories {
            out.append(screen(.calories, "Calories", "Body", "bolt.heart.fill", .orange, ["kcal", "active energy"]))
        }
        if data.drinksTracking {
            out.append(screen(.drinks, "Alcohol", "Log \u{00B7} drinks", "wineglass.fill", .purple, ["alcohol", "drinks", "beer", "wine", "party"]))
        }
        out += [
            screen(.settings, "Settings", "Everything you can change", "gearshape.fill", .indigo, ["preferences"], setting: true),
            screen(.profile, "Profile", "Settings \u{00B7} name, age, setup", "person.fill", .indigo, ["name", "age", "redo setup", "onboarding"], setting: true),
            screen(.conditions, "Health conditions", "Settings \u{00B7} Profile", "heart.text.square.fill", .pink, ["PCOS", "PMDD", "endometriosis", "eating disorder", "migraine"], setting: true),
            screen(.calendars, "Calendars", "Settings \u{00B7} exams from your calendar", "calendar", .yellow, ["Google Calendar", "Apple Calendar", "iCal", "sign in", "connect", "exams"], setting: true),
            screen(.cycleSettings, "Cycle & birth control", "Settings", "drop.fill", .pink, ["pill", "pack", "pill time", "reminder", "birth control", "refill", "method"], setting: true),
            screen(.sleepSettings, "Sleep & alarm", "Settings", "alarm.fill", .purple, ["bedtime", "up by", "alarm", "Watch alarm", "wake time", "backup alarm", "nudge"], setting: true),
            screen(.tracking, "Tracking", "Settings \u{00B7} water, alcohol, calories", "slider.horizontal.3", .blue, ["bottle size", "alcohol", "calories", "quick-log drinks", "units"], setting: true),
            screen(.notifications, "Notifications", "Settings", "bell.fill", .coral, ["alerts", "reminders", "nudges", "sick alerts"], setting: true),
            screen(.widgetsWatch, "Widgets & Watch", "Settings", "applewatch", .indigo, ["widget", "complication", "Lock Screen", "Home Screen", "Watch face"], setting: true),
            screen(.healthData, "Apple Health & data", "Settings", "heart.fill", .pink, ["Apple Health", "permissions", "export", "delete", "example data", "CSV"], setting: true),
            screen(.appearance, "Appearance", "Settings \u{00B7} dark, light or sky", "circle.lefthalf.filled", .purple, ["dark mode", "light mode", "theme", "sky", "sunset", "evening dim"], setting: true),
        ]
        for section in HealthGuide.sections {
            for article in section.articles(for: store.birthControl) {
                out.append(SearchItem(id: "guide.\(article.id)", kind: .article, title: article.title,
                                      note: "Health guide \u{00B7} \(section.title)", systemImage: section.systemImage,
                                      accent: section.accent, target: .article(article)))
            }
        }
        return out
    }
}

/// The search page: the field focused straight away, results grouped as
/// screens, settings and guide articles. Picking one closes search and
/// hands the result back (`onPick`), so it opens on the tab underneath.
struct AppSearchView: View {
    var onPick: (SearchItem) -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var active = true

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var results: [SearchItem] {
        guard !trimmed.isEmpty else { return [] }
        let items = AppSearch.items(model: model, store: store).filter { $0.matches(trimmed) }
        return items.enumerated()
            .sorted { ($0.element.rank(trimmed), $0.offset) < ($1.element.rank(trimmed), $1.offset) }
            .map(\.element)
    }

    var body: some View {
        let found = results
        NavigationStack {
            Screen(accent: .indigo, refreshes: false) {
                if trimmed.isEmpty {
                    Text("Screens, settings and Health guide articles. Try \u{201C}calendar\u{201D}, \u{201C}pill\u{201D} or \u{201C}HRV\u{201D}.")
                        .font(.bodyText)
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.s)
                } else if found.isEmpty {
                    Text("Nothing matches \u{201C}\(trimmed)\u{201D}.")
                        .font(.bodyText)
                        .secondaryText()
                        .padding(.top, Space.s)
                } else {
                    group("Screens", found.filter { $0.kind == .screen })
                    group("Settings", found.filter { $0.kind == .setting })
                    group("Health guide", found.filter { $0.kind == .article })
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $active,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Screens, settings, guide")
            .onChange(of: active) { _, on in
                // Cancel closes search altogether.
                if !on { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(Accent.indigo.ink(scheme))
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [SearchItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                SectionLabel(text: title)
                RowCard {
                    ForEach(Array(items.prefix(12).enumerated()), id: \.element.id) { i, item in
                        if i > 0 { RowDivider() }
                        MetricRow(title: item.title, note: item.note, systemImage: item.systemImage,
                                  accent: item.accent, action: {
                            onPick(item)
                            dismiss()
                        })
                    }
                }
            }
        }
    }
}

// MARK: - Pull down to search

private enum SearchAnchor: Hashable { case content }

/// The search field's height plus the gap under it: how far the page
/// starts scrolled, so the field stays out of sight until she pulls down.
private struct SearchFieldHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A tab root's content with the search field above it (`Screen(searches:
/// true)`). A pick opens on this tab's stack, or switches to its tab.
struct PullDownSearch<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var searching = false
    @State private var picked: SearchItem?
    @State private var opened: SearchItem.Target?
    @State private var tucked = false
    @Environment(\.openTab) private var openTab
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let top = Self.statusBarBottom
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                field
                    // Tucked under the status bar it showed faintly behind
                    // the clock; it fades out as it slides under and back in
                    // as she pulls down.
                    .visualEffect { content, geo in
                        let y = geo.frame(in: .global).minY, h = max(geo.size.height, 1)
                        return content.opacity(min(max(1 - (top - y) / (h * 0.5), 0), 1))
                    }
                    .padding(.top, Space.s)
                    .padding(.bottom, Space.m)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: SearchFieldHeight.self, value: geo.size.height)
                        }
                    }
                content
                    .id(SearchAnchor.content)
            }
            .onAppear {
                // Once: the page opens with the field just out of sight.
                guard !tucked else { return }
                tucked = true
                proxy.scrollTo(SearchAnchor.content, anchor: .top)
            }
        }
        .sheet(isPresented: $searching, onDismiss: openPicked) {
            AppSearchView { picked = $0 }
        }
        .navigationDestination(item: $opened) { target in
            switch target {
            case .screen(let screen): screen.view
            case .article(let article): GuideArticleView(article: article)
            case .tab: EmptyView()
            }
        }
    }

    /// The bottom of the status bar, where the tucked field starts to show.
    private static var statusBarBottom: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow?.safeAreaInsets.top ?? 54
    }

    /// Looks like a search field; tapping it opens search with the keyboard up.
    private var field: some View {
        let p = Palette(scheme: scheme)
        return Button { searching = true } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .accessibilityHidden(true)
                Text("Search screens, settings, guide")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .font(.bodyText)
            .foregroundStyle(p.secondary)
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, minHeight: Sizes.minTap, alignment: .leading)
            .background(p.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
        .accessibilityHint("Screens, settings and Health guide articles")
    }

    private func openPicked() {
        guard let item = picked else { return }
        picked = nil
        if case .tab(let tab) = item.target {
            openTab(tab)
        } else {
            opened = item.target
        }
    }
}

/// On a tab root: when she lets go, the page settles either fully showing
/// the search field or fully hiding it, never half way.
struct SearchScrollBehavior: ViewModifier {
    var enabled: Bool
    @State private var fieldHeight: CGFloat = 0

    func body(content: Content) -> some View {
        if enabled {
            content
                .scrollTargetBehavior(SearchSnap(height: fieldHeight))
                .onPreferenceChange(SearchFieldHeight.self) { fieldHeight = $0 }
        } else {
            content
        }
    }
}

private struct SearchSnap: ScrollTargetBehavior {
    var height: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let y = target.rect.minY
        guard height > 0, y > 0, y < height else { return }
        target.rect.origin.y = y < height / 2 ? 0 : height
    }
}
