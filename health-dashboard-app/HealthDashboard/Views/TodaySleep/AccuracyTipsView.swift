import SwiftUI
import HealthCore

/// A checklist of ways to make the numbers more accurate, each with a
/// one-line why and, where the app can tell, whether it's done.
struct AccuracyTipsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Screen(title: "Accurate numbers", accent: .indigo) {
            Text("Getting accurate numbers")
                .font(.scaled(size: 28, weight: .bold))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)
            summaryCard
            section("Wearing your Watch", watchTips)
            section("Settings on your phone and Watch", settingsTips)
            section("Small daily habits", habitTips)
        }
    }

    // MARK: Statuses

    /// Reading from Apple Health and at least one real night came through.
    private var healthConnected: Bool { model.healthConnection == .connected }
    /// Asked for access; either access is off or no night has come through yet.
    private var waitingForSleep: Bool { model.healthConnection == .noSleepYet }
    /// Real nights from Apple Health (not the example nights).
    private var realNights: Int { model.realNightCount }
    private var checkInsTwoWeeks: Int { model.checkIns(lastDays: 14).count }
    private var caffeineDays: Int { model.daysWithEntries(store.data.drinkLog.map(\.date), lastDays: 7) }
    private var periodDays: Int { model.daysWithEntries(store.data.flowLog.map(\.date), lastDays: 60) }

    private var sampleOnly: TipStatus { .unknown("Connect Apple Health to check this") }

    private var sleepTrackingStatus: TipStatus {
        if waitingForSleep { return .todo("No sleep from Apple Health yet") }
        guard healthConnected else { return sampleOnly }
        return model.nightRecordedThisMorning ? .done("Last night was recorded") : .todo("No night recorded this morning")
    }

    private var sensorsStatus: TipStatus {
        guard healthConnected else { return sampleOnly }
        switch (model.wristTempDelta != nil, model.respiratoryRateDelta != nil) {
        case (true, true): return .done("Wrist temperature and breathing rate are coming in")
        case (true, false): return .todo("Wrist temperature found, no breathing rate yet")
        case (false, true): return .todo("Breathing rate found, no wrist temperature yet")
        case (false, false): return .todo("No wrist temperature or breathing rate yet")
        }
    }

    private var healthStatus: TipStatus {
        switch model.healthConnection {
        case .connected:
            return model.healthWriteDenied
                ? .todo("Reading from Apple Health. Saving to Apple Health is off.")
                : .done("Connected to Apple Health")
        case .noSleepYet:
            // Apple never says whether reading is allowed, so this stays a maybe.
            return .todo("No sleep from Apple Health yet. If you turned off access, open Settings.")
        case .notAsked:
            return .todo("Not connected to Apple Health yet, so these are example numbers")
        case .sampleChosen:
            return .todo("Showing example data (you chose this in Settings)")
        case .unavailable:
            return .unknown("Apple Health isn't available on this device")
        }
    }

    private var daytimeStatus: TipStatus {
        guard healthConnected else { return sampleOnly }
        let hours = model.watchWornHoursToday
        return hours >= 8 ? .done("Heart rate in \(hours) hours today") : .todo("Heart rate in only \(hours) hours today")
    }

    private var checkInStatus: TipStatus {
        let n = checkInsTwoWeeks
        let text = "\(n) of the last 14 mornings"
        return n >= 10 ? .done(text) : .todo(text)
    }

    private var loggingStatus: TipStatus {
        var text = "Caffeine logged on \(caffeineDays) of the last 7 days"
        if store.data.cycleSetup != .notTracking {
            text += ", period on \(periodDays) days in 2 months"
        }
        return caffeineDays >= 4 ? .done(text) : .todo(text)
    }

    private var birthControlStatus: TipStatus {
        switch store.data.cycleSetup {
        case .natural: return .done("Set to: natural cycle, no hormonal birth control")
        case .hormonal:
            if let bc = store.birthControl { return .done("Set to: \(bc.rawValue)") }
            return .todo("Hormonal is on, but no method is picked")
        case .irregular: return .done("Set to: irregular cycles")
        case .notTracking: return .done("Set to: not tracking a cycle")
        }
    }

    private var nightsStatus: TipStatus {
        let n = realNights
        let goal = AppModel.nightsNeeded
        return n >= goal ? .done("\(n) of your nights so far, plenty") : .todo("\(n) of \(goal) of your nights so far")
    }

    private var allStatuses: [TipStatus] {
        [sleepTrackingStatus, sensorsStatus, healthStatus, daytimeStatus, checkInStatus, loggingStatus, birthControlStatus, nightsStatus]
    }

    // MARK: Summary

    private var summaryCard: some View {
        let known = allStatuses.filter { if case .unknown = $0 { return false }; return true }
        let done = known.filter { if case .done = $0 { return true }; return false }.count
        let fraction = known.isEmpty ? 0 : Double(done) / Double(known.count)
        return Card(accent: .indigo) {
            AdaptiveStack(spacing: 16) {
                Ring(value: fraction, accent: .indigo, lineWidth: 10, label: "\(done)/\(known.count)", size: 84,
                     accessibilityText: "\(done) of \(known.count) checks done")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Things the app can check").font(.scaled(size: 17, weight: .bold))
                    Text("Your recovery, sleep need and stress are compared with your own usual, so the more good data the app has, the sharper they get.")
                        .font(.scaled(size: 14))
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Tips

    private var watchTips: [Tip] {
        [
            Tip(icon: "applewatch", accent: .indigo, title: "Wear it to bed, snug",
                why: "One finger's width above your wrist bone. A loose band misses heartbeats and makes HRV and sleep stages less reliable."),
            Tip(icon: "battery.100.bolt", accent: .mint, title: "Charge it before bed",
                why: "Top it up while you shower or get ready, so it lasts the whole night and doesn't miss your sleep."),
            Tip(icon: "figure.walk", accent: .blue, title: "Wear it during the day too",
                why: "Daytime heart rate and HRV are what stress and recovery are built from.", status: daytimeStatus),
            Tip(icon: "wind", accent: .purple, title: "Do a Mindfulness or Breathe session",
                why: "A minute of sitting still gives your Watch an extra, clean HRV reading."),
        ]
    }

    private var settingsTips: [Tip] {
        [
            Tip(icon: "bed.double.fill", accent: .purple, title: "Turn on a sleep schedule or Sleep Focus",
                why: "In the Health app, under Sleep. Apple Watch only tracks sleep when one is set up.", status: sleepTrackingStatus),
            Tip(icon: "thermometer.medium", accent: .coral, title: "Turn on Track Sleep with Apple Watch and Wrist Temperature",
                why: "In the Watch app, under Sleep and under Health. Temperature and breathing rate help spot getting sick and your cycle.",
                status: sensorsStatus),
            Tip(icon: "heart.text.square.fill", accent: .pink, title: "Allow all Health permissions",
                why: "Missing permissions mean missing numbers. In Settings, go to Health, then Data Access & Devices, then this app, and turn on all.",
                status: healthStatus, action: .health),
            Tip(icon: "pills.fill", accent: .pink, title: "Set your birth control correctly",
                why: "Most hormonal methods stop ovulation, which changes what's normal for your heart rate and temperature.",
                status: birthControlStatus, action: .settings),
            Tip(icon: "arrow.down.circle.fill", accent: .indigo, title: "Keep watchOS updated",
                why: "Updates improve sleep and heart tracking. In the Watch app, go to General, then Software Update."),
        ]
    }

    private var habitTips: [Tip] {
        [
            Tip(icon: "sun.horizon.fill", accent: .orange, title: "Do the morning check-in every day",
                why: "How you feel teaches the app your real sleep need and your best wake time.", status: checkInStatus,
                action: model.canCheckInNow && !model.checkInDoneToday ? .checkIn : nil),
            Tip(icon: "cup.and.saucer.fill", accent: .yellow, title: "Log caffeine, drinks and periods",
                why: "So the app can tell a late coffee or a night out apart from a bad night's sleep.", status: loggingStatus),
            Tip(icon: "calendar", accent: .mint, title: "Give it about 2 weeks",
                why: "Your usual needs a couple of weeks of nights. Numbers settle down after that.", status: nightsStatus),
        ]
    }

    private func section(_ title: String, _ tips: [Tip]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title).padding(.horizontal, 4).padding(.top, 6)
            Card(padding: 14) {
                ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                    if index > 0 { Divider() }
                    tipRow(tip)
                }
            }
        }
    }

    private func tipRow(_ tip: Tip) -> some View {
        let p = Palette(scheme: scheme)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.icon)
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(tip.accent.ink(scheme))
                .frame(width: 34, height: 34)
                .background(tip.accent.tint(scheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title).font(.scaled(size: 15, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text(tip.why)
                    .font(.scaled(size: 13))
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let status = tip.status { statusLine(status) }
                if let action = tip.action { actionView(action) }
            }
            Spacer(minLength: 0)
        }
    }

    private func statusLine(_ status: TipStatus) -> some View {
        let (icon, accent, text): (String, Accent, String) = {
            switch status {
            case .done(let t): return ("checkmark.circle.fill", .mint, t)
            case .todo(let t): return ("exclamationmark.circle.fill", .orange, t)
            case .unknown(let t): return ("questionmark.circle", .indigo, t)
            }
        }()
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundStyle(accent.ink(scheme)).accessibilityHidden(true)
            Text(text).foregroundStyle(accent.ink(scheme)).fixedSize(horizontal: false, vertical: true)
        }
        .font(.scaled(size: 13, weight: .semibold))
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actionView(_ action: TipAction) -> some View {
        switch action {
        case .health:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { healthActions }
                VStack(alignment: .leading, spacing: 8) { healthActions }
            }
        case .settings:
            NavigationLink {
                SettingsView()
            } label: {
                actionLabel("Change in Settings")
            }
            .buttonStyle(.plain)
        case .checkIn:
            NavigationLink {
                CheckInView()
            } label: {
                actionLabel("Check in now")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var healthActions: some View {
        let canConnect = model.healthConnection == .notAsked || model.healthConnection == .sampleChosen
        if canConnect {
            Button {
                Task { await model.connectHealth() }
            } label: {
                actionLabel("Connect Apple Health")
            }
            .buttonStyle(.plain)
        }
        if model.healthConnection != .unavailable, let url = URL(string: UIApplication.openSettingsURLString) {
            Link(destination: url) {
                actionLabel("Open Settings")
            }
        }
    }

    private func actionLabel(_ text: String) -> some View {
        Text(text)
            .font(.scaled(size: 13, weight: .bold))
            .foregroundStyle(Accent.indigo.ink(scheme))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Accent.indigo.fill(scheme).opacity(0.16), in: Capsule())
            .contentShape(Capsule())
    }
}

// MARK: - Pieces

private enum TipStatus {
    case done(String)
    case todo(String)
    case unknown(String)
}

private enum TipAction {
    case health, settings, checkIn
}

private struct Tip {
    var icon: String
    var accent: Accent
    var title: String
    var why: String
    var status: TipStatus? = nil
    var action: TipAction? = nil
}
