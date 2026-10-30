import Foundation
import HealthCore

/// Her break weeks behind the HRV, resting heart rate and sleep trends
/// (D-G3), from the same packs the pill-history features read (H-A10,
/// H-E2). A night counts by the day she woke, as in the pack-day baselines.
extension AppModel {
    /// The break days inside `domain`, as spans from the first break day's
    /// midnight to the midnight after the last, up to today. Combined pill
    /// with a pack set and a break, since her last method change; empty
    /// otherwise, so nothing is shaded.
    func breakSpans(in domain: ClosedRange<Date>) -> [ClosedRange<Date>] {
        guard let packs = packCalendar, packs.hasBreak else { return [] }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        let since = pillHistorySince.map { cal.startOfDay(for: $0) } ?? domain.lowerBound
        let from = max(domain.lowerBound, since)
        let to = min(domain.upperBound, tomorrow)
        guard from < to else { return [] }
        return (packs.position(of: from).pack...packs.position(of: to).pack).compactMap { pack in
            let last = packs.date(pack: pack, day: packs.packLength)
            let start = max(packs.date(pack: pack, day: packs.activeDays + 1), from)
            let end = min(cal.date(byAdding: .day, value: 1, to: last) ?? last, to)
            return start < end ? start...end : nil
        }
    }

    /// Whether `day` (a wake day) falls in a shaded break.
    func isBreakDay(_ day: Date) -> Bool {
        guard let position = packPosition(of: day), let packs = packCalendar else { return false }
        return packs.isBreak(day: position.day)
    }
}

/// What's shaded behind the trends: her break weeks on a pack, else the
/// periods she logged when she ovulates on her own (Ashley, Oct 30: a
/// natural cycle had no shading at all). Nothing on methods that stop
/// ovulation without a break, or when she isn't tracking her cycle.
extension AppModel {
    /// The shaded spans inside `domain`.
    func bandSpans(in domain: ClosedRange<Date>) -> [ClosedRange<Date>] {
        shadesPeriods ? periodSpans(in: domain) : breakSpans(in: domain)
    }

    /// Whether `day` (a wake day) falls in a shaded band.
    func isBandDay(_ day: Date) -> Bool {
        guard shadesPeriods else { return isBreakDay(day) }
        return periodDays.contains(Calendar.current.startOfDay(for: day))
    }

    /// The band's name in the key and the readout: "Break week", "Period".
    var bandName: String { shadesPeriods ? "Period" : packBreakName }

    /// For VoiceOver: "break weeks shaded", "periods shaded".
    var bandsSpoken: String { shadesPeriods ? "periods shaded" : "\(breaksPhrase) shaded" }

    private var shadesPeriods: Bool {
        packCalendar?.hasBreak != true && store.data.cycleSetup != .notTracking && !ovulationStopped
    }

    /// The days she logged bleeding (spotting doesn't count), as in `periodLength`.
    private var periodDays: Set<Date> {
        let cal = Calendar.current
        return Set(store.data.flowLog.filter { $0.flow != .none && $0.flow != .spotting }.map { cal.startOfDay(for: $0.date) })
    }

    /// Runs of logged bleeding days, each from its first midnight to the
    /// midnight after its last, clipped to `domain`.
    private func periodSpans(in domain: ClosedRange<Date>) -> [ClosedRange<Date>] {
        let cal = Calendar.current
        var spans: [ClosedRange<Date>] = []
        for day in periodDays.sorted() {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            if let last = spans.last, last.upperBound == day {
                spans[spans.count - 1] = last.lowerBound...next
            } else {
                spans.append(day...next)
            }
        }
        return spans.compactMap { span in
            let start = max(span.lowerBound, domain.lowerBound), end = min(span.upperBound, domain.upperBound)
            return start < end ? start...end : nil
        }
    }
}
