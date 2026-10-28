import SwiftUI
import HealthCore

/// Tonight's plan: "Bed by" first, the sleep dial with the wake time beside
/// it, and the smart alarm in one row.
struct TonightPage: View {
    @EnvironmentObject private var sync: WatchSync
    @EnvironmentObject private var alarm: SmartAlarmManager

    private var snapshot: WatchSnapshot { sync.snapshot }

    var body: some View {
        WatchPage(title: "Tonight", accent: .purple) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 10) {
                    SnapshotStatusLine(snapshot: snapshot, now: context.date)
                    VStack(alignment: .leading, spacing: 10) { plan }
                        .staleStyle(snapshot.isStale(now: context.date))
                }
            }
            SmartAlarmRow(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private var plan: some View {
        if let bed = snapshot.bedtime {
            let bedMinutes = Clock.minutesOfDay(bed)
            VStack(alignment: .leading, spacing: 0) {
                Text("Bed by")
                    .font(WatchStyle.label)
                    .foregroundStyle(Accent.purple.ink(.dark))
                Text(Clock.format(bedMinutes))
                    .font(WatchStyle.number(.title))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            // The phone's plan: best wake time and the sleep it expects (older
            // phone builds only send the alarm window, so fall back to its end).
            if let wake = snapshot.plannedWake ?? snapshot.upBy ?? snapshot.alarmWindowEnd {
                let wakeMinutes = Clock.minutesOfDay(wake)
                HStack(spacing: 10) {
                    SleepDial(bedMinutes: bedMinutes, wakeMinutes: wakeMinutes, asleepMinutes: snapshot.plannedAsleepMinutes)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snapshot.plannedWake == nil ? "Up by" : "Wake")
                            .font(WatchStyle.label)
                            .foregroundStyle(Accent.orange.ink(.dark))
                        Text(Clock.format(wakeMinutes))
                            .font(WatchStyle.number(.title3))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            Text("No plan for tonight yet. Set one on your iPhone.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(WatchStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A 12-hour dial with the sleep arc from bedtime (moon) to wake (sun) and
/// the planned sleep in the middle.
private struct SleepDial: View {
    let bedMinutes: Int
    let wakeMinutes: Int
    /// Sleep the phone's plan expects (time in bed minus falling asleep);
    /// nil from older phone builds, which show time in bed.
    var asleepMinutes: Int? = nil
    @ScaledMetric(relativeTo: .title3) private var scaledSize: CGFloat = 84

    private let lineWidth: CGFloat = 9
    private var size: CGFloat { min(scaledSize, 100) }

    private var duration: Int { ((wakeMinutes - bedMinutes) % 1440 + 1440) % 1440 }
    private var startFraction: Double { Double(bedMinutes % 720) / 720 }
    private var lengthFraction: Double { Double(min(duration, 720)) / 720 }
    private var radius: CGFloat { (size - lineWidth) / 2 }

    /// "8h", or "7h 40m".
    private var durationText: String {
        let shown = asleepMinutes ?? duration
        return shown % 60 == 0 ? "\(shown / 60)h" : Clock.duration(shown)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
                .padding(lineWidth / 2)
            Circle()
                .trim(from: 0, to: lengthFraction)
                .stroke(AngularGradient(colors: [WatchStyle.nightArc, WatchStyle.sunrise], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(lengthFraction, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .padding(lineWidth / 2)
                .rotationEffect(.degrees(-90 + 360 * startFraction))
            endpoint(symbol: "moon.fill", color: Accent.purple.ink(.dark), fraction: startFraction)
            endpoint(symbol: "sun.max.fill", color: WatchStyle.sunrise, fraction: startFraction + lengthFraction)
            VStack(spacing: -1) {
                Text(durationText)
                    .font(WatchStyle.number(.footnote))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(asleepMinutes == nil ? "in bed" : "asleep")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchStyle.secondaryText)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .padding(.horizontal, lineWidth + 6)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep plan from \(Clock.format(bedMinutes)) to \(Clock.format(wakeMinutes)), \(Clock.duration(asleepMinutes ?? duration)) \(asleepMinutes == nil ? "in bed" : "asleep")")
    }

    private func endpoint(symbol: String, color: Color, fraction: Double) -> some View {
        ZStack {
            Circle()
                .fill(WatchStyle.dialKnob)
                .frame(width: 16, height: 16)
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
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

/// The smart alarm in one row: its switch and where it stands ("On ·
/// wakes by 7:45am"), with how it works underneath.
private struct SmartAlarmRow: View {
    let snapshot: WatchSnapshot
    @EnvironmentObject private var alarm: SmartAlarmManager

    private var hasWindow: Bool { snapshot.alarmWindowStart != nil && snapshot.alarmWindowEnd != nil }

    /// The part of the window the Watch actually listens in.
    private var listening: (start: Date, end: Date)? {
        guard let start = snapshot.alarmWindowStart, let end = snapshot.alarmWindowEnd else { return nil }
        return (SmartAlarmManager.listeningStart(of: .init(start: start, end: end)), end)
    }

    /// "7:45am", or "Mon 7:45am" when it isn't within the next day.
    private func when(_ date: Date) -> String {
        if date.timeIntervalSinceNow < 20 * 3600 { return WatchStyle.time(date) }
        return date.formatted(.dateTime.weekday(.abbreviated)) + " " + WatchStyle.time(date)
    }

    /// One short line under "Smart alarm".
    private var status: String {
        switch alarm.status {
        case .off:
            return snapshot.alarmEnabled ? "Off on this Watch" : "Off \u{00B7} turn on in iPhone app"
        case .noWindow:
            return "Waiting for your iPhone"
        case let .scheduled(_, end):
            return alarm.pendingChange ? "Open again to update" : "On \u{00B7} wakes by \(when(end))"
        case let .later(_, end):
            let weekend = snapshot.alarmWeekdaysOnly == true && Calendar.current.isDateInWeekend(Date().addingTimeInterval(24 * 3600))
            return weekend ? "Off for the weekend" : "Next: \(when(end)) latest"
        case .needsForeground:
            return "Open before bed to turn on"
        case let .listening(end):
            return "On \u{00B7} wakes by \(WatchStyle.time(end))"
        case .ringing:
            return "Ringing"
        case let .woke(at):
            return "Woke at \(WatchStyle.time(at))"
        case .failed:
            return "Couldn't turn on"
        }
    }

    /// How it works, or what went wrong, under the row.
    private var detail: String? {
        switch alarm.status {
        case .failed(let message):
            return message
        case .later:
            return "Open this app the evening before to turn it on."
        case .off, .noWindow, .ringing, .woke:
            return nil
        default:
            // The Watch sees movement and heart rate, not sleep stages.
            guard let listening else { return nil }
            let a = Clock.minutesOfDay(listening.start)
            var b = Clock.minutesOfDay(listening.end)
            if b < a { b += 1440 }
            return "Buzzes when you start stirring, \(TimeRange(a, b).label)."
        }
    }

    /// Shows off while the phone has the alarm off or no window, so the
    /// switch never looks on next to "Off".
    private var switchState: Binding<Bool> {
        Binding(get: { alarm.enabledOnWatch && snapshot.alarmEnabled && hasWindow },
                set: { alarm.enabledOnWatch = $0 })
    }

    private var isArmed: Bool {
        switch alarm.status {
        case .scheduled, .listening: return !alarm.pendingChange
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: switchState.animation(.snappy(duration: 0.3))) {
                HStack(spacing: 8) {
                    Image(systemName: isArmed ? "alarm.fill" : "alarm")
                        .font(.headline)
                        .foregroundStyle(Accent.orange.ink(.dark))
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Smart alarm")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isArmed ? Accent.orange.ink(.dark) : WatchStyle.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .contentTransition(.opacity)
                    }
                }
            }
            .tint(WatchStyle.switchOn)
            .disabled(!snapshot.alarmEnabled || !hasWindow)
            .accessibilityHint("Wakes you when you start stirring in your wake window")
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WatchStyle.surface))

            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.3), value: status)
        .sensoryFeedback(.success, trigger: isArmed) { old, new in !old && new }
    }
}
