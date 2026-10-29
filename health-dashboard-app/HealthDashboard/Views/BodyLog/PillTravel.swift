import SwiftUI
import HealthCore

/// Pill time when travelling (H-A11): one line at the top of Cycle while
/// her phone is in another time zone, with the detail in a sheet.
struct PillAwayCallout: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var showing = false

    var body: some View {
        if model.pillAwayFromHome {
            CalloutBar(text: "Away from home? Take your pill at about your home time: \(here) here.",
                       systemImage: "airplane", accent: .indigo) {
                showing = true
            }
            .bottomSheet(isPresented: $showing, title: "Pill time away from home") {
                Text("Keep taking it at about your usual home time; a few hours either way is fine on the combined pill.")
                    .font(.bodyText).fixedSize(horizontal: false, vertical: true)
                Text("Your \(home) at home is \(here) here. Your reminder comes then.")
                    .font(.bodyText).secondaryText().fixedSize(horizontal: false, vertical: true)
                Button("I live here now: remind me at \(home) here") {
                    model.usePillTimeZoneHere()
                    showing = false
                }
                .font(.bodyEmphasis)
                .foregroundStyle(Accent.indigo.ink(scheme))
                .frame(minHeight: 44)
            }
        }
    }

    private var home: String { BodyLogStyle.shortTime(store.data.pillTime) }
    private var here: String { BodyLogStyle.shortTime(model.pillTimeHere) }
}
