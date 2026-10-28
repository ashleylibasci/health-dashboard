import SwiftUI
import HealthCore

/// Settings, opened from the avatar on every tab: a short hub of grouped
/// rows, each showing its current state and pushing its own page
/// (`SettingsPages.swift`). The Health guide is first, and Calendars sits
/// near the top so a signed-out Google Calendar is never hidden.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @ObservedObject private var importer = CalendarImport.shared
    @Environment(\.colorScheme) private var scheme
    /// "dark" (default), "light" or "system". Read by the app root.
    @AppStorage("appearance") private var appearance = "dark"

    var body: some View {
        Screen(title: "Settings", accent: .indigo) {
            profile
            RowCard {
                MetricRow(title: "Health guide", note: "Sleep, sick days, the pill, periods and more",
                          systemImage: "book.closed.fill", accent: .indigo) { HealthGuideView() }
            }
            group("Connections") {
                MetricRow(title: "Calendars", note: importer.stateText, verdict: importer.stateVerdict,
                          systemImage: "calendar", accent: .yellow) { CalendarSettingsView() }
                RowDivider()
                MetricRow(title: "Apple Health & data", note: healthNote,
                          systemImage: "heart.fill", accent: .pink) { DataSettingsView() }
                RowDivider()
                MetricRow(title: "Widgets & Watch", note: "Home Screen, Lock Screen and Watch face",
                          systemImage: "applewatch", accent: .indigo) { WidgetsWatchSettingsView() }
            }
            group("You") {
                MetricRow(title: "Cycle & birth control", note: cycleNote,
                          systemImage: "drop.fill", accent: .pink) { CycleSettingsView() }
                RowDivider()
                MetricRow(title: "Sleep & alarm",
                          note: "Usual bed \(Clock.format(store.data.bedtime)) \u{00B7} up by \(Clock.format(store.data.upBy))",
                          systemImage: "alarm.fill", accent: .purple) { SleepSettingsView() }
                RowDivider()
                MetricRow(title: "Tracking", note: trackingNote,
                          systemImage: "slider.horizontal.3", accent: .blue) { TrackingSettingsView() }
            }
            group("App") {
                MetricRow(title: "Notifications", note: notificationsNote,
                          systemImage: "bell.fill", accent: .coral) { NotificationSettingsView() }
                RowDivider()
                MetricRow(title: "Appearance", note: AppearanceSettingsView.name(appearance),
                          systemImage: "circle.lefthalf.filled", accent: .purple) { AppearanceSettingsView() }
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(text: title)
            RowCard { content() }
        }
    }

    // MARK: Profile

    /// Her name and what the app is learning from; opens Profile.
    private var profile: some View {
        let p = Palette(scheme: scheme)
        return NavigationLink { ProfileSettingsView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.fill")
                    .font(.scaled(size: 24, weight: .semibold))
                    // The same avatar as the tab headers: indigo on the chip
                    // colour, coral being kept for "worse" (Tanaka F1).
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(width: 56, height: 56)
                    .background(p.chip, in: Circle())
                    .overlay(Circle().strokeBorder(p.cardBorder))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.data.name.map { $0.isEmpty ? "Your profile" : $0 } ?? (model.usingSampleData ? "Example profile" : "Your profile"))
                        .font(.scaled(size: 20, weight: .bold))
                    Text(profileDetail).font(.scaled(size: 13)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(p.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.top, Space.xs)
            .padding(.bottom, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Name, age, health conditions and setup")
    }

    private var profileDetail: String {
        if model.prefersSampleData { return "Showing example data (you chose this)" }
        if model.usingSampleData { return "Showing example data until Apple Health has \(AppModel.nightsNeeded) nights" }
        let nights = model.nights.count
        return "Learning your normal from \(nights) night\(nights == 1 ? "" : "s") of sleep"
    }

    // MARK: Row notes

    private var healthNote: String {
        if model.loading { return "Loading\u{2026}" }
        if model.prefersSampleData { return "Example data (you chose this)" }
        return model.usingSampleData ? "Example data for now" : "Connected"
    }

    private var cycleNote: String {
        guard store.data.cycleSetup == .hormonal else { return Self.setupName(store.data.cycleSetup) }
        return store.data.birthControl ?? "Birth control: pick your method"
    }

    private var trackingNote: String {
        var on = ["Water"]
        if store.data.drinksTracking { on.append("alcohol") }
        if store.data.showCalories && !model.caloriesHiddenByCondition { on.append("calories") }
        return on.joined(separator: ", ") + ", quick-log drinks"
    }

    private var notificationsNote: String {
        let on = [store.data.sickAlerts, store.data.peakDipNudges].filter { $0 }.count
        return on == 0 ? "Off" : "\(on) of 2 on"
    }

    static func setupName(_ setup: AppData.CycleSetup) -> String {
        switch setup {
        case .natural: return "Natural cycle"
        case .hormonal: return "Birth control"
        case .irregular: return "Irregular or not sure"
        case .notTracking: return "Not tracking"
        }
    }
}
