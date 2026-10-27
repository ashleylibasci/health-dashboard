import SwiftUI
import HealthCore

/// Tonight's plan: bedtime, wake time, and the smart alarm.
struct TonightPage: View {
    @EnvironmentObject private var sync: WatchSync
    @EnvironmentObject private var alarm: SmartAlarmManager

    private var snapshot: WatchSnapshot { sync.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(title: "Tonight", accent: .purple)
                if snapshot == .empty {
                    NotSyncedView()
                } else {
                    SnapshotStatusLine(snapshot: snapshot)
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 10) { plan }
                            .staleStyle(snapshot.isStale(now: context.date))
                    }
                    SmartAlarmCard(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var plan: some View {
        if let bed = snapshot.bedtime, let wake = snapshot.alarmWindowEnd {
            let bedMinutes = Clock.minutesOfDay(bed)
            let wakeMinutes = Clock.minutesOfDay(wake)
            SleepDial(bedMinutes: bedMinutes, wakeMinutes: wakeMinutes)
                .frame(width: 118, height: 118)
                .frame(maxWidth: .infinity)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("BED BY")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Accent.purple.ink(.dark))
                    Text(Clock.format(bedMinutes))
                        .font(.number(19))
                }
                .accessibilityElement(children: .combine)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("UP AT")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Accent.orange.ink(.dark))
                    Text(Clock.format(wakeMinutes))
                        .font(.number(19))
                }
                .accessibilityElement(children: .combine)
            }
        } else if let bed = snapshot.bedtime {
            VStack(alignment: .leading, spacing: 0) {
                Text("BED BY")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Accent.purple.ink(.dark))
                Text(WatchStyle.time(bed))
                    .font(.number(24))
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("No plan for tonight yet. Set one on your iPhone.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WatchStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A 12-hour dial with the sleep arc from bedtime (moon) to wake (sun).
private struct SleepDial: View {
    let bedMinutes: Int
    let wakeMinutes: Int

    private let lineWidth: CGFloat = 12
    private let size: CGFloat = 118

    private var duration: Int { ((wakeMinutes - bedMinutes) % 1440 + 1440) % 1440 }
    private var startFraction: Double { Double(bedMinutes % 720) / 720 }
    private var lengthFraction: Double { Double(min(duration, 720)) / 720 }
    private var radius: CGFloat { (size - lineWidth) / 2 }

    /// "8h", or "7h 40m".
    private var durationText: String {
        duration % 60 == 0 ? "\(duration / 60)h" : Clock.duration(duration)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: lengthFraction)
                .stroke(LinearGradient(colors: [Color(hex: 0x8E7BFF), Color(hex: 0xFFB27A)],
                                       startPoint: .topTrailing, endPoint: .bottomLeading),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90 + 360 * startFraction))
            ForEach([0, 3, 6, 9], id: \.self) { hour in
                Text(hour == 0 ? "12" : "\(hour)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .offset(offset(fraction: Double(hour) / 12, radius: radius - 18))
            }
            endpoint(symbol: "moon.fill", color: Accent.purple.ink(.dark), fraction: startFraction)
            endpoint(symbol: "sun.max.fill", color: Color(hex: 0xFFB27A), fraction: startFraction + lengthFraction)
            VStack(spacing: 0) {
                Text(durationText)
                    .font(.number(durationText.count > 3 ? 18 : 26))
                    .minimumScaleFactor(0.7)
                Text("of sleep")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WatchStyle.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep plan from \(Clock.format(bedMinutes)) to \(Clock.format(wakeMinutes)), \(Clock.duration(duration)) of sleep")
    }

    private func endpoint(symbol: String, color: Color, fraction: Double) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x1A1245))
                .frame(width: 18, height: 18)
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
        }
        .offset(offset(fraction: fraction, radius: radius))
    }

    /// Position on the dial for a fraction of 12 hours, clockwise from 12.
    private func offset(fraction: Double, radius: CGFloat) -> CGSize {
        let angle = fraction * 2 * Double.pi
        return CGSize(width: radius * CGFloat(sin(angle)), height: -radius * CGFloat(cos(angle)))
    }
}

/// The smart alarm's window, on/off switch and current state.
private struct SmartAlarmCard: View {
    let snapshot: WatchSnapshot
    @EnvironmentObject private var alarm: SmartAlarmManager

    private var hasWindow: Bool { snapshot.alarmWindowStart != nil && snapshot.alarmWindowEnd != nil }

    /// "7:20–7:45am": the part of the window the Watch actually listens in.
    private var windowLabel: String {
        guard let start = snapshot.alarmWindowStart, let end = snapshot.alarmWindowEnd else { return "No wake window" }
        let listen = SmartAlarmManager.listeningStart(of: .init(start: start, end: end))
        let a = Clock.minutesOfDay(listen)
        var b = Clock.minutesOfDay(end)
        if b < a { b += 1440 }
        return TimeRange(a, b).label
    }

    /// "7:45am", or "Mon 7:45am" when it isn't within the next day.
    private func when(_ date: Date) -> String {
        if date.timeIntervalSinceNow < 20 * 3600 { return WatchStyle.time(date) }
        return date.formatted(.dateTime.weekday(.abbreviated)) + " " + WatchStyle.time(date)
    }

    private var statusText: String {
        switch alarm.status {
        case .off:
            return snapshot.alarmEnabled ? "Off on this Watch" : "Turn it on in the iPhone app"
        case .noWindow:
            return "Waiting for a wake window from your iPhone"
        case let .scheduled(start, end):
            let base = "Listens for light sleep from \(when(start)) and wakes you by \(WatchStyle.time(end)) at the latest."
            return alarm.pendingChange ? base + " Open this app to use your new window." : base
        case let .later(_, end):
            let weekend = snapshot.alarmWeekdaysOnly == true && Calendar.current.isDateInWeekend(Date().addingTimeInterval(24 * 3600))
            return (weekend ? "Off for the weekend. " : "") + "Next: \(when(end)) latest. Open this app the evening before to arm it."
        case .needsForeground:
            return "Open this app before bed to arm it"
        case .listening:
            return "Listening for light sleep"
        case .ringing:
            return "Ringing"
        case let .woke(at):
            return "Woke at \(WatchStyle.time(at))"
        case let .failed(message):
            return message
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $alarm.enabledOnWatch) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Smart alarm")
                        .font(.system(size: 15, weight: .semibold))
                    Text(windowLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Accent.orange.ink(.dark))
                }
            }
            .tint(Color(hex: 0x34C759))
            .disabled(!snapshot.alarmEnabled || !hasWindow)
            .accessibilityHint("Wakes you at the first sign of light sleep in your window")

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WatchStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
    }
}
