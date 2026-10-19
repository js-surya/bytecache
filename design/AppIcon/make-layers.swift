import AppKit

// ByteCache icon layers for Icon Composer, following Apple's app icon template:
// 1024×1024 square canvas, no rounded corners (the system masks), background full-bleed,
// foreground artwork as separate transparent layers kept inside the central safe area.
let size = 1024
let out = URL(filePath: CommandLine.arguments[1])

func layer(_ name: String, _ draw: (CGFloat) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: name))
}

// 1 — Background: full-bleed blue gradient.
try layer("1-background.png") { s in
    NSGradient(starting: NSColor(red: 0.22, green: 0.58, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.08, green: 0.27, blue: 0.82, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
}

// 2 — Braces: white "{ }" drawn as glyph outlines (solid shapes, so Icon Composer can light them).
try layer("2-braces.png") { s in
    let font = NSFont.monospacedSystemFont(ofSize: s * 0.44, weight: .bold)
    let text = NSAttributedString(string: "{ }", attributes: [.font: font, .foregroundColor: NSColor.white])
    let ts = text.size()
    text.draw(at: NSPoint(x: s / 2 - ts.width / 2, y: s / 2 - ts.height / 2 + s * 0.035))
}

// 3 — Catch arrow: white down arrow between the braces.
try layer("3-arrow.png") { s in
    let w = s * 0.11, cx = s / 2, top = s * 0.61, bottom = s * 0.40
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: cx, y: top)); arrow.line(to: NSPoint(x: cx, y: bottom))
    arrow.move(to: NSPoint(x: cx - w / 2, y: bottom + w / 2)); arrow.line(to: NSPoint(x: cx, y: bottom))
    arrow.line(to: NSPoint(x: cx + w / 2, y: bottom + w / 2))
    arrow.lineWidth = s * 0.042; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor.white.setStroke(); arrow.stroke()
}

// Preview: layers composited with the iOS corner mask (for checking only; not imported).
try layer("preview.png") { s in
    let clip = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: s * 0.225, yRadius: s * 0.225)
    clip.addClip()
    for name in ["1-background.png", "2-braces.png", "3-arrow.png"] {
        NSImage(contentsOf: out.appending(path: name))!.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    }
}
