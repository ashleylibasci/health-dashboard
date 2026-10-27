import Foundation
import HealthCore

/// Wording shared by the Today, Sleep, Energy and planning screens.
/// Computed only; nothing here is stored. (The long "why there's no cutoff
/// time" copy is `caffeineEarlyOnlyText` in AppModel+UIB.swift, shared with
/// the Log screens.)
extension AppModel {

    /// Short form for a row or chip where a cutoff time would go when the
    /// cutoff falls before she's up: "One small drink early (up to about 85 mg)".
    var caffeineNoCutoffShort: String {
        caffeineLargestDoseAtWake < 5
            ? "Best to skip caffeine today"
            : "One small drink early (up to about \(caffeineLargestDoseAtWake) mg)"
    }

    /// "Last caffeine by 2:30pm." or the one-small-drink line.
    var caffeineCutoffSentence: String {
        if let cutoff = caffeineCutoffShown { return "Last caffeine by \(Clock.format(cutoff))." }
        return caffeineNoCutoffShort + "."
    }
}
