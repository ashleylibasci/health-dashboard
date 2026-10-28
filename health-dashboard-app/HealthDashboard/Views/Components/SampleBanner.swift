import SwiftUI
import UIKit
import HealthCore

/// "Example data · night 3 of 14", shown at the top of a screen while the
/// app is still on example numbers. Renders nothing once the data is hers.
struct SampleDataBanner: View {
    /// On the Log tab: her logs are real even while the numbers are examples.
    var forLog: Bool = false
    /// Today keeps the full "Example data · night 3 of 14" title at the
    /// largest text sizes; other screens show "Example data ⓘ".
    var prominent: Bool = false
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

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

    var body: some View {
        if model.usingSampleData {
            if typeSize.isAccessibilitySize {
                compactBanner
            } else {
                fullBanner
            }
        }
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

    /// At accessibility text sizes the full banner filled the whole first
    /// screen, so it shrinks to one line, "Example data ⓘ", and the why
    /// moves behind the ⓘ. Today (`prominent`) keeps the full title.
    private var compactBanner: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                Text(prominent ? title : "Example data")
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                InfoButton(explanation: Explanation(id: "example-data", title: "Example data",
                                                    meaning: [title + ".", why, accessNote].compactMap { $0 }.joined(separator: " "),
                                                    forYou: ""))
            }
            settingsLink
        }
        .padding(.leading, Space.l)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Accent.yellow.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        .accessibilityElement(children: .contain)
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
