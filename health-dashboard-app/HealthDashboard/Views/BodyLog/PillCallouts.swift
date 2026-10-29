import SwiftUI
import HealthCore

/// One line on Cycle and the Log tab when something she logged matters for
/// her pill: being sick on active pills (H-A7), or spotting on active pills
/// (H-A8). The full note is in a sheet, with a way into the missed-pill
/// helper. At most one line; nothing otherwise.
struct PillLogCallouts: View {
    @EnvironmentObject var model: AppModel
    @State private var showsSick = false
    @State private var showsSpotting = false

    var body: some View {
        if let sick = model.pillSickTrigger {
            CalloutBar(text: sick == .bigNight ? "Sick after a big night? What it means for your pill."
                                               : "Sick on the pill? Under 2 days, no extra pill needed.",
                       systemImage: "cross.case.fill", accent: .yellow) { showsSick = true }
                .bottomSheet(isPresented: $showsSick, title: GuideArticle.sickOnPill.title) {
                    sickSheet(sick)
                }
        } else if model.spottingOnActivePills {
            CalloutBar(text: "Spotting on active pills is common. It isn\u{2019}t a period.",
                       systemImage: "drop.fill", accent: .pink) { showsSpotting = true }
                .bottomSheet(isPresented: $showsSpotting, title: "Spotting on the pill") {
                    spottingSheet
                }
        }
    }

    /// Breakthrough bleeding: expected early on and after a late pill.
    @ViewBuilder
    private var spottingSheet: some View {
        Text("Light bleeding on active pills is called breakthrough bleeding. It\u{2019}s common in the first 3 months on a pill and after a late or missed pill, and the app doesn\u{2019}t count it as a period.")
            .font(.bodyText).fixedSize(horizontal: false, vertical: true)
        Text(model.spottingKeepsHappening
             ? "It\u{2019}s happened in \(model.spottingPacksAfterThreeMonths) of your last 3 packs, after your first 3 months. Worth mentioning at your next pill visit."
             : "If it keeps happening after your first 3 months, mention it at your next pill visit.")
            .font(.bodyText).fixedSize(horizontal: false, vertical: true)
        RowCard {
            MetricRow(title: "Late with a pill?", note: "Two taps to what to do now",
                      systemImage: "exclamationmark.circle.fill", accent: .yellow) {
                MissedPillHelper()
            }
        }
    }

    @ViewBuilder
    private func sickSheet(_ sick: AppModel.PillSickTrigger) -> some View {
        if sick == .bigNight {
            Text("Throwing up after drinking counts the same as a stomach bug. Feeling sick without throwing up doesn\u{2019}t affect your pill.")
                .font(.bodyText).fixedSize(horizontal: false, vertical: true)
        }
        ForEach(GuideArticle.sickOnPill.body, id: \.self) { block in
            if case let .bullets(items) = block {
                ForEach(items, id: \.self) { SheetBullet(text: $0, accent: .yellow) }
            }
        }
        if let source = GuideArticle.sickOnPill.source {
            Text(source).font(.secondary).secondaryText().fixedSize(horizontal: false, vertical: true)
        }
        RowCard {
            MetricRow(title: "Missed a pill as well?", note: "Two taps to what to do now",
                      systemImage: "exclamationmark.circle.fill", accent: .yellow) {
                MissedPillHelper()
            }
        }
    }
}

/// A dot and a line, for sheets.
struct SheetBullet: View {
    var text: String
    var accent: Accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(accent.fill(scheme)).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
            Text(text).font(.bodyText).fixedSize(horizontal: false, vertical: true)
        }
    }
}
