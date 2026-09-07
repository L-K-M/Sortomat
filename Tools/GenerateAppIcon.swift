#!/usr/bin/env swift
//
// GenerateAppIcon.swift — regenerate Sortomat's app icon natively on macOS.
//
// Draws the same brand-green tile + white "sorting funnel" as
// Tools/generate_icon.py, but via Core Graphics. The committed PNGs are
// produced by the Python script so they build on any box; use this on a Mac if
// you would rather regenerate with AppKit.
//
// The geometry is Apple's macOS icon grid and must match the Python script
// exactly: the body is 824 of a 1024 canvas, centred, with a 185.4 corner
// radius — a fraction of the *body*, not of the canvas. An icon drawn edge to
// edge renders about a quarter larger than every neighbour in the Dock,
// because the system scales them all the same.
//
// Usage: swift Tools/GenerateAppIcon.swift [OUTPUT_APPICONSET_DIR]
//
import AppKit

let ladder: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

let top = NSColor(srgbRed: 0x4F / 255.0, green: 0x9E / 255.0, blue: 0x74 / 255.0, alpha: 1)
let bottom = NSColor(srgbRed: 0x2F / 255.0, green: 0x6B / 255.0, blue: 0x4C / 255.0, alpha: 1)
let glyph = NSColor(srgbRed: 0xF6 / 255.0, green: 0xFB / 255.0, blue: 0xF8 / 255.0, alpha: 1)

// Apple's macOS icon grid, in points on a 1024 canvas.
let canvas: CGFloat = 1024
let bodySide: CGFloat = 824
let cornerRadius: CGFloat = 185.4

/// The funnel, relative to the *body* rather than the canvas.
let funnelPoints: [(CGFloat, CGFloat)] = [
    (0.20, 0.24), (0.80, 0.24), (0.595, 0.51),
    (0.595, 0.78), (0.405, 0.78), (0.405, 0.51),
]

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let scale = size / canvas
    let body = bodySide * scale
    let origin = (size - body) / 2
    let rect = NSRect(x: origin, y: origin, width: body, height: body)
    let radius = cornerRadius * scale
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(starting: top, ending: bottom)!
    squircle.addClip()
    // Over the body, not the canvas: the margin is transparent, so a
    // canvas-wide gradient would start part-way through its own ramp.
    gradient.draw(in: rect, angle: -90)

    // Funnel (y measured from the top; flip for AppKit's bottom-left origin).
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: origin + x * body, y: origin + (1 - y) * body)
    }
    let funnel = NSBezierPath()
    for (index, point) in funnelPoints.enumerated() {
        let target = p(point.0, point.1)
        if index == 0 { funnel.move(to: target) } else { funnel.line(to: target) }
    }
    funnel.close()
    glyph.setFill()
    funnel.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sortomat/Resources/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (pt, scale) in ladder {
    let px = CGFloat(pt * scale)
    let rep = render(px)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let name = "\(outDir)/icon_\(pt)x\(pt)@\(scale)x.png"
    try? data.write(to: URL(fileURLWithPath: name))
    print("wrote \(name) (\(Int(px))px)")
}
print("Done.")
