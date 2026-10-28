import SwiftUI
import HealthCore

/// Heavy flow logged with tiredness (or a resting heart rate creeping
/// up): one line suggesting a ferritin test, the rest in a sheet (D3).
/// About 40% of US females aged 12–21 are iron deficient (Weyand 2023).
/// Shows nothing otherwise.
struct IronPromptCallout: View {
    @EnvironmentObject var model: AppModel
    @State private var showsMore = false

    var body: some View {
        if let prompt = model.ironPrompt {
            CalloutBar(text: "Heavy flow and tired? Ask for a ferritin test.", systemImage: "drop.triangle.fill",
                       accent: .pink) { showsMore = true }
                .bottomSheet(isPresented: $showsMore, title: "Iron and heavy periods") {
                    Text(Self.why(prompt))
                        .font(.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Low iron is common and fixable: about 4 in 10 young women in the US are low. A ferritin blood test shows your iron stores, so it\u{2019}s worth asking for one.")
                        .font(.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Iron-rich foods (meat, beans, lentils, tofu, fortified cereal) go further with some vitamin C. Coffee and tea cut how much you absorb, so have them an hour away from meals.")
                        .font(.secondary).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
        }
    }

    /// "You logged heavy flow on 2 days and felt tired around then."
    static func why(_ p: (heavyDays: Int, tired: Bool, heartUp: Bool)) -> String {
        var also: [String] = []
        if p.tired { also.append("felt tired around then") }
        if p.heartUp { also.append("your resting heart rate is running above your usual") }
        return "You logged heavy flow on \(p.heavyDays) days recently, and \(also.joined(separator: ", and ")). Heavy periods are the most common reason young women run low on iron, and tiredness and a faster resting heart rate are signs of it."
    }
}
