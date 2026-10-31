// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import AppKit

// The logo: a flared notch hanging from the top of an orange tile, with the app's
// signature utilities (music, timer, system levels) dropping out of it.
let output = CommandLine.arguments[1]

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
        green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func notchPath(in r: NSRect, flare f: CGFloat, corner c: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: r.minX, y: r.maxY))
    path.curve(
        to: NSPoint(x: r.minX + f, y: r.maxY - f),
        controlPoint1: NSPoint(x: r.minX + f * 0.6, y: r.maxY),
        controlPoint2: NSPoint(x: r.minX + f, y: r.maxY - f * 0.4)
    )
    path.line(to: NSPoint(x: r.minX + f, y: r.minY + c))
    path.curve(
        to: NSPoint(x: r.minX + f + c, y: r.minY),
        controlPoint1: NSPoint(x: r.minX + f, y: r.minY + c * 0.4),
        controlPoint2: NSPoint(x: r.minX + f + c * 0.4, y: r.minY)
    )
    path.line(to: NSPoint(x: r.maxX - f - c, y: r.minY))
    path.curve(
        to: NSPoint(x: r.maxX - f, y: r.minY + c),
        controlPoint1: NSPoint(x: r.maxX - f - c * 0.4, y: r.minY),
        controlPoint2: NSPoint(x: r.maxX - f, y: r.minY + c * 0.4)
    )
    path.line(to: NSPoint(x: r.maxX - f, y: r.maxY - f))
    path.curve(
        to: NSPoint(x: r.maxX, y: r.maxY),
        controlPoint1: NSPoint(x: r.maxX - f, y: r.maxY - f * 0.4),
        controlPoint2: NSPoint(x: r.maxX - f * 0.6, y: r.maxY)
    )
    path.close()
    return path
}

func render(_ pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's macOS icon grid: an 824/1024 tile with a 185/1024 corner.
    let inset = s * 0.098
    let tileRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: s * 0.181, yRadius: s * 0.181)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.022
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    color(0xFF6A1F).setFill()
    tile.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current?.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: color(0xFFB72E), ending: color(0xFF4A1C))!.draw(in: tileRect, angle: -90)

    // The notch hangs from the tile's top edge, flaring into it like the real one.
    let notchHeight = s * 0.235
    let notchWidth = s * 0.56
    let notchRect = NSRect(
        x: (s - notchWidth) / 2,
        y: tileRect.maxY - notchHeight,
        width: notchWidth,
        height: notchHeight
    )
    let notch = notchPath(in: notchRect, flare: s * 0.05, corner: s * 0.075)
    NSGraphicsContext.current?.saveGraphicsState()
    let lift = NSShadow()
    lift.shadowColor = color(0x7A1E00).withAlphaComponent(0.55)
    lift.shadowBlurRadius = s * 0.035
    lift.shadowOffset = NSSize(width: 0, height: -s * 0.014)
    lift.set()
    NSColor.black.setFill()
    notch.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // The camera lens, so the shape reads as a notch even at small sizes.
    let lens = s * 0.05
    color(0x23262E).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: s / 2 - lens / 2,
        y: notchRect.minY + notchHeight * 0.5 - lens / 2,
        width: lens,
        height: lens
    )).fill()
    color(0x3D5A9E).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: s / 2 - lens * 0.2,
        y: notchRect.minY + notchHeight * 0.5 - lens * 0.2,
        width: lens * 0.4,
        height: lens * 0.4
    )).fill()

    // Three glyphs in a row, centred in the space under the notch.
    let centerY = (tileRect.minY + notchRect.minY) / 2 + s * 0.005
    let spacing = s * 0.225
    let glyph = s * 0.135

    // Music: a rounded play triangle.
    let playX = s / 2 - spacing
    let play = NSBezierPath()
    play.move(to: NSPoint(x: playX - glyph * 0.42, y: centerY + glyph * 0.56))
    play.line(to: NSPoint(x: playX + glyph * 0.58, y: centerY))
    play.line(to: NSPoint(x: playX - glyph * 0.42, y: centerY - glyph * 0.56))
    play.close()
    play.lineJoinStyle = .round
    play.lineWidth = s * 0.024
    NSColor.white.setFill()
    NSColor.white.setStroke()
    play.fill()
    play.stroke()

    // Timer: a ring that's three-quarters run.
    let ring = NSBezierPath()
    ring.appendArc(
        withCenter: NSPoint(x: s / 2, y: centerY),
        radius: glyph * 0.56,
        startAngle: 90,
        endAngle: 180,
        clockwise: true
    )
    ring.lineWidth = s * 0.038
    ring.lineCapStyle = .round
    NSColor.white.setStroke()
    ring.stroke()

    // Levels: three bars.
    let barsX = s / 2 + spacing
    let barWidth = s * 0.034
    for (index, height) in [CGFloat(0.8), 1.5, 1.1].enumerated() {
        let h = glyph * height
        let x = barsX + CGFloat(index - 1) * barWidth * 1.75 - barWidth / 2
        NSColor.white.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: x, y: centerY - h / 2, width: barWidth, height: h),
            xRadius: barWidth / 2, yRadius: barWidth / 2
        ).fill()
    }
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size).png"))
    try render(size * 2).write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size)@2x.png"))
}
