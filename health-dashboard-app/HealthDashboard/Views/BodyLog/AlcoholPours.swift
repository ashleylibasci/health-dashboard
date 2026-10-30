import SwiftUI
import HealthCore

/// How big a pour was, as pictures (a glass, a can, a red cup, a shot),
/// each with its standard drinks: "a red cup of wine ≈ 3 drinks". Party
/// pours run 2 to 3 standard drinks, so "1 wine" undercounts (D2).
/// Used by the Alcohol screen's log card and the Log tab's pour sheet.
struct PourChoices: View {
    var kind: String
    @Binding var selection: String
    /// Called on every tap (the Log tab logs straight away).
    var onPick: ((AlcoholPour) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let pours = AlcoholPour.pours(for: kind)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s),
                                 count: typeSize.isAccessibilitySize ? 1 : 3), spacing: Space.s) {
            ForEach(pours) { pour in
                PourTile(pour: pour, selected: selection == pour.id) {
                    withMotion(.select) { selection = pour.id }
                    onPick?(pour)
                }
            }
        }
    }
}

/// One pour: the picture, its name and about how many standard drinks.
struct PourTile: View {
    var pour: AlcoholPour
    var selected: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    static func drinksText(_ d: Double) -> String {
        d == 1 ? "1 drink" : "\u{2248} \(AlcoholPour.format(d)) drinks"
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
        let ax = typeSize.isAccessibilitySize
        Button(action: action) {
            // Picture over the words in a row of three; beside them, one
            // per row, at accessibility text sizes.
            let text = VStack(alignment: ax ? .leading : .center, spacing: 2) {
                Text(pour.label)
                    .font(.secondary).fontWeight(.bold)
                    .foregroundStyle(p.primary)
                    .multilineTextAlignment(ax ? .leading : .center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.drinksText(pour.standardDrinks))
                    .font(.small).fontWeight(.semibold)
                    .foregroundStyle(Accent.berry.ink(scheme))
            }
            Group {
                if ax {
                    HStack(spacing: Space.m) {
                        PourPicture(picture: pour.picture).frame(width: 40, height: 40)
                        text
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s)
                } else {
                    VStack(spacing: Space.xs) {
                        PourPicture(picture: pour.picture).frame(height: 40)
                        text
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: ax ? Sizes.minTap : 96)
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.xs)
            .background(selected ? Accent.berry.fill(scheme).opacity(0.22) : p.chip, in: shape)
            .overlay(shape.strokeBorder(selected ? Accent.berry.fill(scheme) : p.cardBorder, lineWidth: selected ? 2 : 1))
            .motion(.select, value: selected)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pour.label), \(pour.size), about \(AlcoholPour.format(pour.standardDrinks)) standard drink\(pour.standardDrinks == 1 ? "" : "s")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A simple drawing of the pour, so a red cup looks like one. Decorative:
/// the tile's label says what it is.
struct PourPicture: View {
    var picture: AlcoholPour.Picture
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = Accent.berry.fill(scheme)
        Group {
            switch picture {
            case .glass:
                Image(systemName: "wineglass.fill").font(.system(size: 24)).foregroundStyle(ink)
            case .bigGlass:
                Image(systemName: "wineglass.fill").font(.system(size: 34)).foregroundStyle(ink)
            case .can:
                can(height: 26)
            case .tallCan:
                can(height: 36)
            case .redCup:
                ZStack(alignment: .top) {
                    Tumbler(topInset: 0, bottomInset: 0.18).fill(Color(hex: 0xE5383B))
                    // The white rim band and the ridge lines of a party cup.
                    Rectangle().fill(.white.opacity(0.9)).frame(height: 3).padding(.top, 2)
                    Rectangle().fill(.black.opacity(0.18)).frame(height: 1.5).padding(.top, 12).padding(.horizontal, 3)
                }
                .frame(width: 28, height: 36)
            case .cocktail:
                CocktailGlass().fill(ink).frame(width: 28, height: 32)
            case .shot:
                Tumbler(topInset: 0, bottomInset: 0.15).fill(ink).frame(width: 14, height: 16)
            case .doubleShot:
                Tumbler(topInset: 0, bottomInset: 0.15).fill(ink).frame(width: 16, height: 26)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func can(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3).fill(Accent.berry.fill(scheme))
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.55)).frame(height: 2).padding(.top, 3).padding(.horizontal, 2)
        }
        .frame(width: 16, height: height)
    }
}

/// A cup wider at the top than the bottom.
private struct Tumbler: Shape {
    /// Inset of each top / bottom corner, as a share of the width.
    var topInset: CGFloat
    var bottomInset: CGFloat

    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + r.width * topInset, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - r.width * topInset, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - r.width * bottomInset, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + r.width * bottomInset, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// A coupe on a stem.
private struct CocktailGlass: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX + 1.5, y: r.minY + r.height * 0.5))
            p.addLine(to: CGPoint(x: r.midX + 1.5, y: r.maxY - 2))
            p.addLine(to: CGPoint(x: r.midX + r.width * 0.3, y: r.maxY - 2))
            p.addLine(to: CGPoint(x: r.midX + r.width * 0.3, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX - r.width * 0.3, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX - r.width * 0.3, y: r.maxY - 2))
            p.addLine(to: CGPoint(x: r.midX - 1.5, y: r.maxY - 2))
            p.addLine(to: CGPoint(x: r.midX - 1.5, y: r.minY + r.height * 0.5))
            p.closeSubpath()
        }
    }
}
