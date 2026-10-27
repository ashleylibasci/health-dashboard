import SwiftUI
import UIKit
import HealthCore

/// "Example data · night 3 of 14", shown at the top of a screen while the
/// app is still on example numbers. Renders nothing once the data is hers.
struct SampleDataBanner: View {
    /// On the Log tab: her logs are real even while the numbers are examples.
    var forLog: Bool = false
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

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
            let p = Palette(scheme: scheme)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Accent.yellow.ink(scheme))
                        .accessibilityAddTraits(.isHeader)
                    Text(why)
                        .font(.footnote)
                        .foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let accessNote {
                        Text(accessNote)
                            .font(.footnote)
                            .foregroundStyle(p.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link(destination: url) {
                                Text("Open Settings")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Accent.yellow.ink(scheme))
                                    .frame(minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Accent.yellow.tint(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }
}
