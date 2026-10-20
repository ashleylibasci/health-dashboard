import SwiftUI

/// How to get better readings for one metric.
struct AccuracyTipsView: View {
    var metric: TrackedMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(plain: "Getting accurate ", accent: "numbers")
            Card(fill: .lavender) {
                CardLabel(metric.title)
                Text(metric.intro).scaledFont(15).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(metric.tips.enumerated()), id: \.offset) { i, tip in
                Card {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(i + 1)").scaledFont(15, .bold).foregroundStyle(Color.mainText).limitedTextGrowth()
                            .frame(width: 28, height: 28).background(Color.lavender, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tip.title).scaledFont(15, .bold).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                            Note(tip.detail)
                        }
                    }
                }
            }
        }
        .detailPage()
    }
}

/// The link at the bottom of a metric's screen.
struct AccuracyLink: View {
    var metric: TrackedMetric
    var body: some View {
        NavigationLink { AccuracyTipsView(metric: metric) } label: {
            LinkCard(icon: "scope", title: "Getting accurate numbers", detail: "Small habits that help your Watch measure this better")
        }
        .buttonStyle(.plain)
    }
}

/// The one data heads-up on Today, with a way to hide it for two weeks.
struct NudgeCard: View {
    var nudge: DataNudge
    var hide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { AccuracyTipsView(metric: nudge.metric) } label: {
                HStack(spacing: 12) {
                    AdaptiveStack(spacing: 12) {
                        Image(systemName: "scope").scaledFont(18).foregroundStyle(Color.mintInk).limitedTextGrowth()
                            .frame(width: 40, height: 40).background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nudge.title).scaledFont(15, .bold).foregroundStyle(Color.ink)
                            Text(nudge.detail).scaledFont(13).foregroundStyle(Color.muted).multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").scaledFont(13, .bold).foregroundStyle(Color.muted).limitedTextGrowth()
                }
            }
            .buttonStyle(.plain)
            Button("Not now", action: hide)
                .scaledFont(13, .semibold).foregroundStyle(Color.mintInk)
                .frame(minHeight: 32)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.mint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
