import SwiftUI
import Charts
import HealthCore

// The one-page summary for her pill visit (G1): a plain US Letter page she
// shares as a PDF from the share sheet. Black on white, fixed sizes, so it
// prints the same whatever her text size or theme.

/// The screen: the page as it will print, and Share.
struct VisitSummaryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var summary: VisitSummary?
    @State private var file: URL?

    var body: some View {
        Screen(title: "Pill visit summary", accent: .indigo) {
            Text("One page with your pill, missed pills, bleeds, symptoms and mood by pack, to share or print before your visit. It\u{2019}s made on your phone and only leaves it if you share it.")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            if let file {
                ShareLink(item: file, preview: SharePreview("Pill visit summary", image: Image(systemName: "doc.richtext"))) {
                    Label("Share the PDF", systemImage: "square.and.arrow.up")
                        .font(.bodyEmphasis)
                        .foregroundStyle(scheme == .dark ? Color(hex: 0x10122A) : .white)
                        .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
                        .background(scheme == .dark ? Accent.indigo.fill(.dark) : Accent.indigo.ink(.light),
                                    in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                }
            }
            if let summary {
                GeometryReader { geo in
                    VisitSummaryPage(summary: summary)
                        .scaleEffect(geo.size.width / VisitSummaryPage.size.width, anchor: .topLeading)
                }
                .aspectRatio(VisitSummaryPage.size.width / VisitSummaryPage.size.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .accessibilityElement(children: .combine)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task {
            let bp = await model.latestBloodPressure()
            guard let made = model.visitSummary(bloodPressure: bp) else { return }
            summary = made
            file = VisitSummaryPage.writePDF(made)
        }
    }
}

/// The printed page.
struct VisitSummaryPage: View {
    let summary: VisitSummary
    static let size = CGSize(width: 612, height: 792)

    private let ink = Color(white: 0.08)
    private let muted = Color(white: 0.38)
    private let rule = Color(white: 0.82)
    private let breakShade = Color(red: 0.93, green: 0.36, blue: 0.52)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            section("My pill") {
                line("\(summary.method). Pill time \(summary.pillTime).")
                line("On this pill since: \(summary.since.map { $0.formatted(.dateTime.month(.wide).day().year()) } ?? "not recorded in the app")")
            }
            section("Missed pills") {
                line(missedLine)
            }
            section("Each pack") { packTable }
            section("Symptoms logged") {
                if summary.symptoms.isEmpty {
                    line("None logged.")
                } else {
                    line(summary.symptoms.map { "\($0.name) \($0.days) day\($0.days == 1 ? "" : "s") (\($0.inBreak) in the \(summary.breakName))" }
                        .joined(separator: " \u{00B7} "))
                }
                if let pattern = summary.pattern {
                    line("Standing out in my last \(BreakWeekPattern.packsNeeded) \(summary.breakName)s: \(pattern.joined(separator: ", ")).", bold: true)
                }
            }
            section("Mood by pack day") { moodBlock }
            section("Blood pressure") {
                line(summary.bloodPressure.map { "Latest in Apple Health (past year): \($0)." } ?? "None in Apple Health in the past year.")
            }
            Spacer(minLength: 0)
            Text("Made with Health Dashboard from what I logged on my iPhone. Missed means no dose was marked taken; days before I started marking pills aren\u{2019}t counted. A pack\u{2019}s bleed includes days that ran into the next pack. Ratings are 1 to 5, once a day.")
                .font(.system(size: 7.5)).foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(36)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(ink)
        .environment(\.colorScheme, .light)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pill visit summary").font(.system(size: 20, weight: .bold))
                if summary.isExample {
                    Text("EXAMPLE DATA").font(.system(size: 8, weight: .bold)).foregroundStyle(breakShade)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(breakShade, lineWidth: 0.8))
                }
                Spacer()
                Text(summary.made.formatted(.dateTime.month(.wide).day().year())).font(.system(size: 9)).foregroundStyle(muted)
            }
            Text("\(summary.range) \u{00B7} the last \(summary.packCount) packs, newest first")
                .font(.system(size: 9.5)).foregroundStyle(muted)
            Rectangle().fill(ink).frame(height: 1.2).padding(.top, 4)
        }
    }

    private var missedLine: String {
        let total = summary.missedTotal
        let days = "marked taken on \(summary.takenDays) of \(summary.judgedDays) pill days"
        guard total > 0 else { return "None: \(days)." }
        return "\(total) missed: \(days). Which ones are in the table below."
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 8.5, weight: .bold)).kerning(0.6).foregroundStyle(muted)
            content()
        }
    }

    private func line(_ text: String, bold: Bool = false) -> some View {
        Text(text).font(.system(size: 10.5, weight: bold ? .semibold : .regular))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var packTable: some View {
        let columns: [(String, CGFloat)] = [("Pack", 128), ("Missed", 88), ("Bleed", 70), ("Heaviest", 76), ("Spotting on active pills", 160)]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(columns, id: \.0) { c in
                    Text(c.0).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(muted).frame(width: c.1, alignment: .leading)
                }
            }
            .padding(.bottom, 3)
            ForEach(summary.packs, id: \.self) { p in
                Rectangle().fill(rule).frame(height: 0.75)
                HStack(spacing: 0) {
                    Text(p.dates + (p.isCurrent ? " (now)" : "")).frame(width: columns[0].1, alignment: .leading)
                    Text(p.missed.isEmpty ? "0" : "\(p.missed.count): pill \(p.missed.map(String.init).joined(separator: ", "))")
                        .frame(width: columns[1].1, alignment: .leading)
                    Text(p.isCurrent && p.bleedDays == 0 ? "\u{2013}" : "\(p.bleedDays) day\(p.bleedDays == 1 ? "" : "s")")
                        .frame(width: columns[2].1, alignment: .leading)
                    Text(p.heaviest).frame(width: columns[3].1, alignment: .leading)
                    Text(p.activeSpotting == 0 ? "None" : "\(p.activeSpotting) day\(p.activeSpotting == 1 ? "" : "s")")
                        .frame(width: columns[4].1, alignment: .leading)
                }
                .font(.system(size: 10))
                .padding(.vertical, 3.5)
            }
            Rectangle().fill(rule).frame(height: 0.75)
        }
    }

    @ViewBuilder
    private var moodBlock: some View {
        if summary.mood.isEmpty {
            line("No ratings logged.")
        } else {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("").frame(width: 96, alignment: .leading)
                        Text("Active pills").frame(width: 62, alignment: .leading)
                        Text(summary.breakName.prefix(1).uppercased() + summary.breakName.dropFirst()).frame(width: 62, alignment: .leading)
                    }
                    .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(muted)
                    .padding(.bottom, 3)
                    ForEach(summary.mood, id: \.self) { m in
                        Rectangle().fill(rule).frame(height: 0.75)
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(m.title)
                                Text(m.scaleNote).font(.system(size: 7)).foregroundStyle(muted)
                            }
                            .frame(width: 96, alignment: .leading)
                            Text(m.active.map { String(format: "%.1f", $0) } ?? "\u{2013}").frame(width: 62, alignment: .leading)
                            Text(m.breakDays.map { String(format: "%.1f", $0) } ?? "\u{2013}").frame(width: 62, alignment: .leading)
                        }
                        .font(.system(size: 10))
                        .padding(.vertical, 3)
                    }
                }
                if let chart = summary.moodChart, chart.isReady { moodChart(chart) }
            }
        }
    }

    private func moodSummary(_ data: MoodByPackDay) -> String {
        guard let lo = data.averages.min(by: { $0.value < $1.value }), let hi = data.averages.max(by: { $0.value < $1.value }) else {
            return "Mood by pack day: no ratings yet."
        }
        return "Mood by pack day, 1 to 5, averaged over your packs, \(summary.breakName.lowercased()) shaded: lowest \(String(format: "%.1f", lo.value)) on day \(lo.key), highest \(String(format: "%.1f", hi.value)) on day \(hi.key)."
    }

    /// Mood (1–5) averaged by pack day, the break shaded.
    private func moodChart(_ data: MoodByPackDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Mood, average by pack day").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(muted)
            Chart {
                if summary.activeDays < summary.packLength {
                    RectangleMark(xStart: .value("Break start", Double(summary.activeDays) + 0.5),
                                  xEnd: .value("Break end", Double(summary.packLength) + 0.5))
                        .foregroundStyle(breakShade.opacity(0.15))
                }
                ForEach(data.points, id: \.self) { pt in
                    PointMark(x: .value("Pack day", Double(pt.day)), y: .value("Rating", pt.value))
                        .foregroundStyle(Color(white: 0.55))
                        .symbolSize(14)
                }
                ForEach((1...summary.packLength).filter { data.averages[$0] != nil }, id: \.self) { d in
                    LineMark(x: .value("Pack day", Double(d)), y: .value("Average", data.averages[d] ?? 0))
                        .foregroundStyle(ink)
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXScale(domain: 0.5...(Double(summary.packLength) + 0.5))
            .chartYScale(domain: 0.5...5.5)
            .chartXAxis { AxisMarks(values: [1, 7, 14, 21, summary.packLength].map(Double.init)) { v in
                AxisGridLine().foregroundStyle(rule)
                AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))").font(.system(size: 7)) }
            } }
            .chartYAxis { AxisMarks(position: .leading, values: [1, 3, 5]) { v in
                AxisGridLine().foregroundStyle(rule)
                AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))").font(.system(size: 7)) }
            } }
            .frame(width: 250, height: 92)
            // One sentence for VoiceOver (D-A2) instead of every dot.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(moodSummary(data))
            Text("Shaded: \(summary.breakName). Grey dots: each day rated.").font(.system(size: 7)).foregroundStyle(muted)
        }
    }

    // MARK: PDF

    /// Writes the page as a one-page PDF in the temporary folder (and, on
    /// demo data, in Documents, for the preview). Nil if it couldn't.
    @MainActor
    static func writePDF(_ summary: VisitSummary) -> URL? {
        let name = "Pill visit summary \(summary.made.formatted(.iso8601.year().month().day())).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let renderer = ImageRenderer(content: VisitSummaryPage(summary: summary))
        renderer.proposedSize = ProposedViewSize(size)
        var ok = false
        renderer.render { _, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        guard ok else { return nil }
        if DemoMode.isOn, let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let copy = docs.appendingPathComponent("visit-summary.pdf")
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: url, to: copy)
        }
        return url
    }
}
