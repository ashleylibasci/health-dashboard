import Foundation
import HealthCore

/// The nap window (H-C2): until when a short nap won't cost tonight's sleep.
extension AppModel {
    /// A nap of this length or less is the one the window is for.
    static let napMinutes = 20

    /// The latest time to start a 20-minute nap today: the earlier of 7
    /// hours after she woke and 8 hours before tonight's bedtime, rounded
    /// down to 10 minutes. Nil without a night recorded this morning.
    var napCutoff: Minutes? {
        guard lastNightIsFresh else { return nil }
        let afterWaking = lastNight.wake + 7 * 60
        let beforeBed = 1440 + tonightBedtime - 8 * 60
        return min(afterWaking, beforeBed) / 10 * 10
    }

    /// Whether the nap window is worth showing now: after waking and until
    /// 3 hours before tonight's bedtime.
    var showsNapWindow: Bool {
        guard napCutoff != nil else { return false }
        return now >= lastNight.wake && now < 1440 + tonightBedtime - 180
    }
}
