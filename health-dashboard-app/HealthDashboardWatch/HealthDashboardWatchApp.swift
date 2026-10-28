import SwiftUI
import WatchKit
import HealthCore

/// The Watch app: four glanceable pages (Recovery, Energy, Tonight, Log) fed
/// by the snapshot the iPhone sends, plus the smart alarm.
@main
@MainActor
struct HealthDashboardWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var sync: WatchSync
    @StateObject private var alarm: SmartAlarmManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _sync = StateObject(wrappedValue: WatchSync.shared)
        _alarm = StateObject(wrappedValue: SmartAlarmManager.shared)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(sync)
                .environmentObject(alarm)
                .task {
                    // WatchSync is activated by WatchAppDelegate at launch (and
                    // asks the phone for numbers once activation completes).
                    // Ask here too, in case it already was.
                    sync.requestSnapshot()
                    // Heart rate, for the smart alarm. (Drinks logged here are saved to
                    // Apple Health by the phone.)
                    if HealthKitService.isAvailable, !WatchHealth.demo { try? await WatchHealth.service.requestAuthorization() }
                    alarm.update(with: sync.snapshot)
                }
                .onChange(of: sync.snapshot) { _, snapshot in
                    alarm.update(with: snapshot)
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // watchOS only lets us schedule the alarm session while the app
                    // is active, so try again every time the app comes forward
                    // (including the first launch). Also ask the phone for fresh
                    // numbers.
                    if phase == .active {
                        alarm.update(with: sync.snapshot)
                        sync.requestSnapshot()
                    }
                }
        }
    }
}

/// Receives the scheduled smart-alarm session when watchOS launches the app
/// in the background at the start of the wake window.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            // Once connected, tell the phone whether tomorrow's alarm is armed.
            WatchSync.shared.onActivated = { SmartAlarmManager.shared.reportStatus(force: true) }
            WatchSync.shared.activate()
        }
    }

    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in SmartAlarmManager.shared.adopt(extendedRuntimeSession) }
    }
}

/// One HealthKitService for the whole Watch app.
enum WatchHealth {
    static let service = HealthKitService()
    /// Debug builds: `-demo` never asks for Apple Health, like the phone's
    /// demo mode. The numbers still come from the phone.
    #if DEBUG
    static let demo = ProcessInfo.processInfo.arguments.contains("-demo")
    #else
    static let demo = false
    #endif
}

// MARK: - Root

struct WatchRootView: View {
    @EnvironmentObject private var alarm: SmartAlarmManager

    var body: some View {
        if alarm.isRinging {
            AlarmView()
        } else {
            WatchPagesView()
        }
    }
}

struct WatchPagesView: View {
    @EnvironmentObject private var sync: WatchSync
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var page = WatchPagesView.startPage(bedtime: nil)
    /// When the app last went to the background, so a return after a long
    /// break opens on the page that fits the time of day again.
    @State private var backgroundedAt: Date?

    var body: some View {
        // One NavigationStack around the pages: each page puts its title in
        // the toolbar, next to the clock, instead of using the top of the
        // screen for it.
        NavigationStack {
            TabView(selection: $page) {
                RecoveryPage(openEnergy: { withAnimation(.snappy(duration: 0.35)) { page = 1 } })
                    .containerBackground(glow(.indigo), for: .tabView)
                    .tag(0)
                EnergyPage()
                    .containerBackground(glow(.mint), for: .tabView)
                    .tag(1)
                TonightPage()
                    .containerBackground(glow(.purple), for: .tabView)
                    .tag(2)
                LogPage()
                    .containerBackground(glow(.yellow), for: .tabView)
                    .tag(3)
            }
            .tabViewStyle(.verticalPage)
        }
        // A tapped complication opens its page (healthnext://page/2).
        .onOpenURL { url in
            if url.host == "page", let n = Int(url.lastPathComponent), (0...3).contains(n) { page = n }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = .now
            case .active:
                // Back after an hour or more: start where the time of day
                // points, as on a fresh launch.
                if let away = backgroundedAt, Date().timeIntervalSince(away) > 3600, !Self.pageArgument {
                    page = Self.startPage(bedtime: sync.snapshot.bedtime)
                }
                backgroundedAt = nil
            default:
                break
            }
        }
    }

    /// The glow behind a page, dimmed in always-on.
    private func glow(_ accent: Accent) -> RadialGradient {
        WatchStyle.glow(accent, dimmed: luminanceReduced)
    }

    /// Debug builds: `-page 2` was passed.
    private static var pageArgument: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-page")
        #else
        return false
        #endif
    }

    /// The page for the time of day: Recovery in the morning, Energy through
    /// the day, Tonight from two hours before bed (or 8pm) until 4am.
    /// Debug builds: `-page 2` opens on that page (0 Recovery, 1 Energy,
    /// 2 Tonight, 3 Log), for simulator screenshots.
    static func startPage(bedtime: Date?, now: Date = .now, calendar: Calendar = .current) -> Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-page"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        let minutes = Clock.minutesOfDay(now, calendar: calendar)
        // Two hours before bed, kept between 6pm and 10pm (a 12:30am
        // bedtime counts as 24:30).
        var eveningStart = 20 * 60
        if let bedtime {
            let bed = Clock.minutesOfDay(bedtime, calendar: calendar)
            eveningStart = min(max((bed < 12 * 60 ? bed + 1440 : bed) - 120, 18 * 60), 22 * 60)
        }
        if minutes < 4 * 60 || minutes >= eveningStart { return 2 }
        if minutes < 11 * 60 { return 0 }
        return 1
    }
}

// MARK: - Shared Watch styling

/// The Watch is always dark, so every color uses the `.dark` tokens.
/// Colors that aren't in the shared palette live here, so the pages don't
/// carry their own hex values.
enum WatchStyle {
    static let palette = Palette(scheme: .dark)
    /// Secondary text on the tinted backgrounds (#C3C7E6 in the designs).
    static let secondaryText = Color(hex: 0xC3C7E6)
    /// Small labels and axis text.
    static let tertiaryText = Color.white.opacity(0.62)
    /// Rows and chips on the page backgrounds.
    static let surface = Color.white.opacity(0.1)
    /// The lighter start of the recovery ring.
    static let recoveryRingStart = Color(hex: 0x9AA6FF)
    /// The sleep arc runs from night (indigo violet) to sunrise (peach).
    static let nightArc = Color(hex: 0x8E7BFF)
    static let sunrise = Color(hex: 0xFFB27A)
    /// The dark disc behind the dial's moon and sun.
    static let dialKnob = Color(hex: 0x1A1245)
    /// Secondary text on the yellow Log page.
    static let caffeineText = Color(hex: 0xE6DAB0)
    /// Secondary text on the ringing alarm.
    static let alarmText = Color(hex: 0xE6D2BC)
    static let alarmGlow = [Color(hex: 0x7A3A00), Color(hex: 0x331700), .black]
    /// The system's switch green.
    static let switchOn = Color.green

    /// The colored glow at the top of each page, fading to black. Always-on
    /// keeps only a faint trace of it.
    static func glow(_ accent: Accent, dimmed: Bool = false) -> RadialGradient {
        let strength = dimmed ? 0.18 : 1
        return RadialGradient(colors: [accent.fill(.dark).opacity(0.55 * strength), accent.fill(.dark).opacity(0.14 * strength), .black],
                              center: UnitPoint(x: 0.2, y: 0), startRadius: 0, endRadius: 200)
    }

    /// "2:00pm" for a date.
    static func time(_ date: Date) -> String {
        Clock.format(Clock.minutesOfDay(date))
    }

    /// Rounded bold numbers with even-width digits, on a text style so they
    /// follow the Watch's text size.
    static func number(_ style: Font.TextStyle) -> Font {
        .system(style, design: .rounded, weight: .bold).monospacedDigit()
    }

    /// Small caption labels ("Bed by", "Wake").
    static let label: Font = .footnote.weight(.semibold)
}

/// A Watch page: the title in the toolbar beside the clock, with an "EX"
/// badge on example data, and the content in a scroll view under it.
struct WatchPage<Content: View>: View {
    let title: String
    let accent: Accent
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var sync: WatchSync
    private static var end: String { "end" }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if sync.snapshot == .empty {
                        NotSyncedView()
                    } else {
                        content()
                    }
                    Color.clear.frame(height: 0).id(Self.end)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: sync.snapshot == .empty) {
                // Debug builds: `-scrollToEnd` shows the bottom of each page,
                // for simulator screenshots.
                #if DEBUG
                guard ProcessInfo.processInfo.arguments.contains("-scrollToEnd"), sync.snapshot != .empty else { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                reader.scrollTo(Self.end, anchor: .bottom)
                #endif
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                PageTitle(title: title, accent: accent, isSample: sync.snapshot.isSample == true)
            }
        }
    }
}

/// "Recovery" in the page's accent color, plus "EX" while the phone shows
/// example data.
struct PageTitle: View {
    let title: String
    let accent: Accent
    let isSample: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.headline)
                .foregroundStyle(accent.ink(.dark))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if isSample {
                Text("EX")
                    .font(.system(.caption2, design: .rounded, weight: .heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Accent.yellow.ink(.dark)))
                    .accessibilityLabel("Example data")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Freshness

extension WatchSnapshot {
    /// 4am on the app day that contains `now` (the day rolls over at 4am).
    static func appDayStart(for now: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: now)
        let rollover = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: midnight) ?? midnight
        if now >= rollover { return rollover }
        return calendar.date(byAdding: .day, value: -1, to: rollover) ?? rollover
    }

    /// The numbers are from an earlier app day (before this morning's 4am
    /// rollover): recovery, energy and today's caffeine aren't today's, so
    /// the pages don't show them. Unknown (older phone build) counts as today.
    func isFromEarlierDay(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let syncedAt else { return false }
        return syncedAt < Self.appDayStart(for: now, calendar: calendar)
    }

    /// Older than 6 hours, or from an earlier app day: greyed out and
    /// marked with their time.
    func isStale(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let syncedAt else { return false }
        if now.timeIntervalSince(syncedAt) > 6 * 3600 { return true }
        return isFromEarlierDay(now: now, calendar: calendar)
    }

    /// "As of 9:40am", or "As of Mon 9:40pm" from another day, once the
    /// snapshot is more than 15 minutes old.
    func asOfText(now: Date = Date()) -> String? {
        guard let syncedAt, now.timeIntervalSince(syncedAt) > 15 * 60 else { return nil }
        let sameDay = Calendar.current.isDate(syncedAt, inSameDayAs: now)
        let day = sameDay ? "" : syncedAt.formatted(.dateTime.weekday(.abbreviated)) + " "
        return "As of \(day)\(WatchStyle.time(syncedAt))"
    }
}

/// "As of 9:40am" under a page title. Empty when the numbers are current.
/// (Example data is marked in the title.)
struct SnapshotStatusLine: View {
    let snapshot: WatchSnapshot
    var now: Date = .now

    var body: some View {
        if let asOf = snapshot.asOfText(now: now) {
            Text(asOf)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// From an earlier day: say so instead of showing yesterday's numbers.
struct NotTodayView: View {
    let what: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No \(what) for today yet")
                .font(.headline)
            Text("Open Health Dashboard on your iPhone to update.")
                .font(.footnote)
                .foregroundStyle(WatchStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Greys out numbers that are out of date.
    func staleStyle(_ stale: Bool) -> some View {
        self.saturation(stale ? 0 : 1).opacity(stale ? 0.55 : 1)
    }
}

/// Buttons and tiles: a quick press-in, then spring back.
struct WatchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Shown until the first snapshot arrives from the iPhone.
struct NotSyncedView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(WatchStyle.secondaryText)
                .accessibilityHidden(true)
            Text("Open Health Dashboard on your iPhone to sync.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(WatchStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
