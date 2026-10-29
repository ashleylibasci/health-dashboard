import Foundation

/// "Late or missed a pill?" in one answer (H-A2): the CDC's combined-pill
/// rules (US SPR 2024) for the pack days she missed. The app knows her
/// pack, so she only says how many and since when.
public enum MissedPill {
    /// What to do, as flags the app words (`CycleCare.missedPillAnswer`).
    public struct Advice: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            /// Only break pills (no hormones): nothing to make up.
            case breakPillsOnly
            /// One active pill late or missed (under 48 hours): take it now,
            /// keep going, no backup.
            case oneLate
            /// Two or more in a row (48 hours or more): take the latest now,
            /// skip the other missed ones, backup for 7 days.
            case twoOrMore
        }
        public var kind: Kind
        /// Missed in the last active week: finish the active pills and
        /// start the next pack with no break.
        public var skipBreak: Bool
        /// Missed in the first active week (a late pack start counts):
        /// emergency contraception is worth asking about after sex in the
        /// last 5 days.
        public var emergencyWorthIt: Bool
        /// Days of condoms (or no sex) needed: 0 or 7.
        public var backupDays: Int { kind == .twoOrMore ? 7 : 0 }

        public init(kind: Kind, skipBreak: Bool = false, emergencyWorthIt: Bool = false) {
            self.kind = kind
            self.skipBreak = skipBreak
            self.emergencyWorthIt = emergencyWorthIt
        }
    }

    /// The answer for the pack days she missed (in order, oldest first).
    /// Break days among them don't count; the rest decide it: one active
    /// pill is "late", two or more is "missed".
    public static func advice(missedDays: [Int], activeDays: Int, packLength: Int) -> Advice {
        let active = missedDays.filter { $0 >= 1 && $0 <= activeDays }
        guard !active.isEmpty else { return Advice(kind: .breakPillsOnly) }
        guard active.count >= 2 else { return Advice(kind: .oneLate) }
        let hasBreak = activeDays < packLength
        let lastWeek = hasBreak && active.contains { $0 > activeDays - 7 }
        let firstWeek = active.contains { $0 <= 7 }
        return Advice(kind: .twoOrMore, skipBreak: lastWeek, emergencyWorthIt: firstWeek)
    }

    /// The pack days from `firstMissed` through `latestDue`, wrapping into
    /// the next pack (pill 27, 28, 1, 2).
    public static func span(from firstMissed: Int, through latestDue: Int, packLength: Int) -> [Int] {
        var out = [firstMissed]
        var d = firstMissed
        while d != latestDue, out.count < packLength {
            d = d % packLength + 1
            out.append(d)
        }
        return out
    }
}
