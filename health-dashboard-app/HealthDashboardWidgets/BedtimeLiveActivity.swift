import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import HealthCore

/// The bedtime Live Activity (D-W1) on the Lock Screen and in the Dynamic
/// Island: "Bed in 45 min", "Bed by 11:50pm · up 8:30am", and the Watch
/// alarm ("Watch alarm on", "Watch alarm: open app on your Watch", or a
/// "Turn on Watch alarm" button). Purple, the app's sleep colour. Once it's
/// past its time (2am) it just says good night.
struct BedtimeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BedtimeActivityAttributes.self) { context in
            BedtimeLockScreen(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(Accent.purple.ink(.dark))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        BedIn(bedtime: state.bedtime, stale: context.isStale)
                    } icon: {
                        Image(systemName: "moon.fill").foregroundStyle(Accent.purple.ink(.dark))
                    }
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("up \(time(state.upAt))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bed by \(time(state.bedtime))")
                            .font(.subheadline.weight(.semibold))
                        AlarmLine(alarm: state.alarm)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "moon.fill")
                    .foregroundStyle(Accent.purple.ink(.dark))
                    .accessibilityLabel("Bedtime")
            } compactTrailing: {
                Text(time(state.bedtime))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Accent.purple.ink(.dark))
                    .accessibilityLabel("Bed by \(time(state.bedtime))")
            } minimal: {
                Image(systemName: "moon.fill")
                    .foregroundStyle(Accent.purple.ink(.dark))
                    .accessibilityLabel("Bed by \(time(state.bedtime))")
            }
            .keylineTint(Accent.purple.ink(.dark))
        }
    }
}

private struct BedtimeLockScreen: View {
    let context: ActivityViewContext<BedtimeActivityAttributes>

    var body: some View {
        let state = context.state
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.title2)
                .foregroundStyle(Accent.purple.ink(.dark))
                .frame(width: 40, height: 40)
                .background(Accent.purple.fill(.dark).opacity(0.25), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                BedIn(bedtime: state.bedtime, stale: context.isStale)
                    .font(.headline)
                if !context.isStale {
                    Text("Bed by \(time(state.bedtime)) \u{00B7} up \(time(state.upAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    AlarmLine(alarm: state.alarm)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

/// "Bed in 45 min", counting down on its own; "Sleep well" once it's over.
private struct BedIn: View {
    let bedtime: Date
    let stale: Bool

    var body: some View {
        if stale {
            Text("Sleep well")
        } else if #available(iOS 18.0, *) {
            Text("Bed \(Text(.currentDate, format: .reference(to: bedtime, allowedFields: [.hour, .minute])))")
        } else {
            Text("Bed in \(Text(bedtime, style: .relative))")
        }
    }
}

/// "Watch alarm on", "Watch alarm: open app on your Watch", or
/// a "Turn on Watch alarm" button. Nothing without a Watch.
private struct AlarmLine: View {
    let alarm: BedtimeActivityAttributes.WatchAlarm

    var body: some View {
        switch alarm {
        case .on:
            Label("Watch alarm on", systemImage: "alarm.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Accent.orange.ink(.dark))
        case .openWatch:
            Label("Watch alarm: open app on your Watch", systemImage: "applewatch")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .off:
            Button(intent: TurnOnWatchAlarmIntent()) {
                Label("Turn on Watch alarm", systemImage: "alarm")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(Accent.orange.fill(.dark))
        case .hidden:
            EmptyView()
        }
    }
}

/// "11:50pm", like everywhere in the app.
private func time(_ date: Date) -> String { Clock.format(Clock.minutesOfDay(date)) }
