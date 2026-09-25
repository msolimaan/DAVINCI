// Draws the app icon (a glowing gradient squircle with sparkles) and writes a .iconset folder.
// Usage: swift scripts/make-icon.swift Support/AppIcon.iconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Support/AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // macOS icon grid: the squircle is ~80% of the canvas with room for the shadow.
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset * 1.15, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.shadowBlurRadius = size * 0.03
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let background = NSGradient(colors: [
        NSColor(red: 0.16, green: 0.04, blue: 0.42, alpha: 1),
        NSColor(red: 0.64, green: 0.09, blue: 0.60, alpha: 1),
        NSColor(red: 0.96, green: 0.45, blue: 0.82, alpha: 1),
    ])
    background?.draw(in: rect, angle: -60)

    // Soft glow behind the glyph.
    let glowRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
    let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.45), NSColor.white.withAlphaComponent(0)])
    glow?.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

    // Glass highlight on the top half.
    let highlight = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), xRadius: radius, yRadius: radius)
    NSColor.white.withAlphaComponent(0.08).setFill()
    highlight.fill()
    NSGraphicsContext.restoreGraphicsState()

    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.4, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let glyph = symbol.withSymbolConfiguration(configuration) {
            let glyphSize = glyph.size
            let origin = NSPoint(x: rect.midX - glyphSize.width / 2, y: rect.midY - glyphSize.height / 2)
            glyph.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
    return image
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])?.write(to: url)
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try writePNG(drawIcon(size: CGFloat(pixels)), pixels: pixels, to: output.appendingPathComponent(name))
    }
}
print("Wrote \(output.path)")
