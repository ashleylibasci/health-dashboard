import SwiftUI
import HealthCore

/// "Last pack: refill by Nov 20" as a row (H-A6). Tapping it sets how many
/// packs she has, in a sheet. For a `RowCard`.
struct RefillRow: View {
    @EnvironmentObject var model: AppModel
    @State private var editing = false
    @State private var packs = 1

    var body: some View {
        MetricRow(title: model.refillTitle, note: model.refillNote,
                  systemImage: "shippingbox.fill", accent: model.packsLeftNow.map { $0 <= 1 } == true ? .yellow : .indigo) {
            packs = max(model.packsLeftNow ?? 1, 1)
            editing = true
        }
        .bottomSheet(isPresented: $editing, title: "Packs left") {
            Text("Count the pack you\u{2019}re on. Set it again when you pick up a refill.")
                .font(.bodyText).secondaryText().fixedSize(horizontal: false, vertical: true)
            Stepper(value: $packs, in: 1...13) {
                Text("\(packs) pack\(packs == 1 ? "" : "s")").font(.cardTitle)
            }
            .frame(minHeight: 44)
            Text("You\u{2019}ll get a reminder a week before you run out, or a week before Thanksgiving or winter break if you\u{2019}d run out over it. It only says \u{201C}Your 10am reminder\u{201D} on the lock screen.")
                .font(.secondary).secondaryText().fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Save", accent: .indigo) {
                model.setPacksLeft(packs)
                editing = false
            }
        }
    }
}
