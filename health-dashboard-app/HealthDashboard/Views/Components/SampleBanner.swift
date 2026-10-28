import SwiftUI
import UIKit
import HealthCore

/// "Example data · night 3 of 14", shown at the top of a screen while the
/// app is still on example numbers. Renders nothing once the data is hers.
///
/// Two sizes (Valtonen F14, Whitfield F15; structure review, Oct 28):
/// - Today (`prominent`), the first day it shows: the full banner, with why
///   and the Apple Health note.
/// - Everywhere else, Today included after that first day (and at
///   accessibility text sizes): a small "Example data" capsule that opens
///   the why, so the banner no longer pushes Recovery down the screen.
///   While Apple Health hasn't sent any sleep, Today keeps a one-line
///   banner instead, for its "Open Settings" link.
struct SampleDataBanner: View {
    /// On the Log tab: her logs are real even while the numbers are examples.
    var forLog: Bool = false
    /// Today: the full banner the first day, then one line. Other screens
    /// show the small capsule.
    var prominent: Bool = false
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// When Today first showed the full banner (seconds since 1970; 0 = never).
    @AppStorage("exampleBannerFirstSeen") private var firstSeen: Double = 0
    @State private var showingWhy = false

    private var nights: Int { min(model.realNightCount, AppModel.nightsNeeded) }

    private var title: String {
        nights == 0 ? "Example data · no nights yet" : "Example data · night \(nights) of \(AppModel.nightsNeeded)"
    }

    private var why: String {
        var text = baseWhy
        if forLog { text = "Your logs are saved; the numbers around them are examples. " + text }
        if model.healthConnection == .sampleChosen { text += " You chose example data in Settings." }
        return text
    }

    /// Apple never says whether reading is allowed, so this is worded as a maybe.
    private var accessNote: String? {
        model.healthConnection == .noSleepYet
            ? "No sleep from Apple Health yet. If you turned off access, open Settings."
            : nil
    }

    private var baseWhy: String {
        if nights == 0 {
            return "These numbers aren't yours. Wear your Watch to bed; your own appear after \(AppModel.nightsNeeded) nights."
        }
        let lastNight = model.lastNightIsReal ? " Last night is already yours." : ""
        return "Most numbers here aren't yours yet. Your own appear after \(AppModel.nightsNeeded) nights.\(lastNight)"
    }

    private var explanation: Explanation {
        Explanation(id: "example-data", title: "Example data",
                    meaning: [title + ".", why, accessNote].compactMap { $0 }.joined(separator: " "),
                    forYou: "")
    }

    /// The full banner on Today until the end of the first day it showed.
    private var showsFullBanner: Bool {
        guard prominent, !typeSize.isAccessibilitySize else { return false }
        guard firstSeen > 0 else { return true }
        return Calendar.current.isDateInToday(Date(timeIntervalSince1970: firstSeen))
    }

    var body: some View {
        // Fades out (and the page closes up) when her own numbers take over.
        Group {
            if model.usingSampleData {
                Group {
                    if showsFullBanner {
                        fullBanner
                            .onAppear { if firstSeen == 0 { firstSeen = Date.now.timeIntervalSince1970 } }
                    } else if prominent && accessNote != nil {
                        compactBanner
                    } else {
                        capsule
                    }
                }
                .motionTransition(.commit, edge: .top)
            }
        }
        .motion(.commit, value: model.usingSampleData)
    }

    /// The full banner: icon, title, why, and the access note.
    private var fullBanner: some View {
        let p = Palette(scheme: scheme)
        return HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodyEmphasis)
                        .foregroundStyle(Accent.yellow.ink(scheme))
                    Text(why)
                        .font(.secondary)
                        .foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let accessNote {
                        Text(accessNote)
                            .font(.secondary)
                            .foregroundStyle(p.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // One element, so VoiceOver reads the words and never the icon.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenText)
                .accessibilityAddTraits(.isHeader)
                settingsLink
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Accent.yellow.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// One line, "Example data · night 3 of 14 ⓘ", with the why behind
    /// the ⓘ and the "Open Settings" link under it. Today after the first
    /// day while Apple Health has sent no sleep.
    private var compactBanner: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.xs) {
                Text(title)
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                InfoButton(explanation: explanation)
            }
            settingsLink
        }
        .padding(.leading, Space.l)
        .padding(.vertical, Space.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Accent.yellow.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// The small "Example data" capsule, on every screen (Today after its
    /// first day). Tapping it opens why the numbers aren't hers yet.
    private var capsule: some View {
        Button { showingWhy = true } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.scaled(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Example data")
                    .font(.scaled(size: 13, weight: .semibold))
                Image(systemName: "info.circle")
                    .font(.scaled(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Accent.yellow.onTint(scheme))
            .padding(.horizontal, 10)
            .frame(minHeight: Font.scaledSize(26))
            .background(Accent.yellow.fill(scheme).opacity(0.2), in: Capsule())
            .frame(minHeight: Sizes.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, -Space.s)
        .accessibilityLabel("Example data. \(title)")
        .accessibilityHint("Explains why these numbers aren't yours yet")
        .sheet(isPresented: $showingWhy) { ExplanationSheet(explanation: explanation) }
    }

    private var icon: some View {
        Image(systemName: "doc.text.magnifyingglass")
            .font(.scaled(size: 17, weight: .semibold))
            .foregroundStyle(Accent.yellow.ink(scheme))
            .accessibilityHidden(true)
    }

    private var spokenText: String {
        [title + ".", why, accessNote].compactMap { $0 }.joined(separator: " ")
    }

    @ViewBuilder
    private var settingsLink: some View {
        if accessNote != nil, let url = URL(string: UIApplication.openSettingsURLString) {
            Link(destination: url) {
                Text("Open Settings")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
    }
}
