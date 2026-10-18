import AppKit

// Draws the Health Dashboard icon: a recovery ring (72%) around a moon, Morning light palette.
func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

enum Style { case light, dark, tinted, watch }

func render(_ style: Style, to path: String) {
    let size: CGFloat = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Background
    switch style {
    case .light, .watch:
        let g = NSGradient(starting: color(0xF1F2FF), ending: color(0xDCE0FF))!
        g.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
    case .dark:
        let g = NSGradient(starting: color(0x1C1F3A), ending: color(0x0E1022))!
        g.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
    case .tinted:
        // Tinted icons are drawn in grayscale on transparent; iOS applies the tint.
        break
    }

    let center = CGPoint(x: size / 2, y: size / 2)
    let radius: CGFloat = style == .watch ? 300 : 330
    let line: CGFloat = style == .watch ? 92 : 100

    // Ring track
    ctx.setLineWidth(line)
    ctx.setLineCap(.round)
    let track: NSColor = style == .dark ? color(0x2B3160) : style == .tinted ? color(0xFFFFFF, 0.35) : color(0xFFFFFF)
    ctx.setStrokeColor(track.cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Ring progress: 72%, starting at 12 o'clock, going clockwise.
    let progress: NSColor = style == .tinted ? color(0xFFFFFF) : color(0x7C8CF8)
    ctx.setStrokeColor(progress.cgColor)
    let start = CGFloat.pi / 2
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: start - 0.72 * .pi * 2, clockwise: true)
    ctx.strokePath()

    // Moon and stars in the middle.
    let moonColor: NSColor = style == .dark ? color(0xA3AEFF) : style == .tinted ? color(0xFFFFFF) : color(0x4453C9)
    let config = NSImage.SymbolConfiguration(pointSize: style == .watch ? 300 : 330, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [moonColor]))
    if let symbol = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: center.x - s.width / 2 + 10, y: center.y - s.height / 2, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
render(.light, to: out + "/icon-light.png")
render(.dark, to: out + "/icon-dark.png")
render(.tinted, to: out + "/icon-tinted.png")
render(.watch, to: out + "/icon-watch.png")
print("ok")
