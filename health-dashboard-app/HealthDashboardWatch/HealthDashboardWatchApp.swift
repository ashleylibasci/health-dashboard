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
                    if HealthKitService.isAvailable { try? await WatchHealth.service.requestAuthorization() }
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
    var body: some View {
        TabView {
            RecoveryPage()
                .containerBackground(WatchStyle.glow(.indigo), for: .tabView)
            EnergyPage()
                .containerBackground(WatchStyle.glow(.mint), for: .tabView)
            TonightPage()
                .containerBackground(WatchStyle.glow(.purple), for: .tabView)
            LogPage()
                .containerBackground(WatchStyle.glow(.yellow), for: .tabView)
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Shared Watch styling

/// The Watch is always dark, so every color uses the `.dark` tokens.
enum WatchStyle {
    static let palette = Palette(scheme: .dark)
    /// Secondary text on the tinted backgrounds (#C3C7E6 in the designs).
    static let secondaryText = Color(hex: 0xC3C7E6)

    /// The colored glow at the top of each page, fading to black.
    static func glow(_ accent: Accent) -> RadialGradient {
        RadialGradient(colors: [accent.fill(.dark).opacity(0.55), accent.fill(.dark).opacity(0.14), .black],
                       center: UnitPoint(x: 0.2, y: 0), startRadius: 0, endRadius: 200)
    }

    /// "2:00pm" for a date.
    static func time(_ date: Date) -> String {
        Clock.format(Clock.minutesOfDay(date))
    }
}

/// Page title in the page's accent color, as in the designs.
struct PageHeader<Trailing: View>: View {
    let title: String
    let accent: Accent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent.ink(.dark))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, accent: Accent) {
        self.init(title: title, accent: accent, trailing: { EmptyView() })
    }
}

// MARK: - Freshness

extension WatchSnapshot {
    /// Older than 6 hours, or from before this morning's 4am rollover: the
    /// numbers are yesterday's or out of date. Unknown (older phone build)
    /// counts as fresh.
    func isStale(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let syncedAt else { return false }
        if now.timeIntervalSince(syncedAt) > 6 * 3600 { return true }
        let midnight = calendar.startOfDay(for: now)
        let rollover = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: midnight) ?? midnight
        return now >= rollover && syncedAt < rollover
    }

    /// "As of 9:40am" once the snapshot is more than 15 minutes old.
    func asOfText(now: Date = Date()) -> String? {
        guard let syncedAt, now.timeIntervalSince(syncedAt) > 15 * 60 else { return nil }
        let sameDay = Calendar.current.isDate(syncedAt, inSameDayAs: now)
        let day = sameDay ? "" : syncedAt.formatted(.dateTime.weekday(.abbreviated)) + " "
        return "As of \(day)\(WatchStyle.time(syncedAt))"
    }
}

/// "Example data" and "As of 9:40am" under a page title. Empty when the
/// numbers are hers and current.
struct SnapshotStatusLine: View {
    let snapshot: WatchSnapshot

    var body: some View {
        TimelineView(.everyMinute) { context in
            let parts = [snapshot.isSample == true ? "Example data" : nil, snapshot.asOfText(now: context.date)].compactMap { $0 }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(snapshot.isSample == true ? Accent.yellow.ink(.dark) : WatchStyle.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// Greys out numbers that are out of date.
    func staleStyle(_ stale: Bool) -> some View {
        self.saturation(stale ? 0 : 1).opacity(stale ? 0.55 : 1)
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WatchStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
