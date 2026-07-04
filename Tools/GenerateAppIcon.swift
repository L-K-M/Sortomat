#!/usr/bin/env swift
//
// GenerateAppIcon.swift — regenerate Sortomat's app icon natively on macOS.
//
// Draws the same brand-green squircle + white "sorting funnel" as
// Tools/generate_icon.py, but via Core Graphics (nicer anti-aliasing). The
// committed PNGs are produced by the Python script so they build on any box;
// use this on a Mac if you'd rather regenerate with AppKit.
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

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.225
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(starting: top, ending: bottom)!
    squircle.addClip()
    gradient.draw(in: rect, angle: -90)

    // Funnel (y measured from the top; flip for AppKit's bottom-left origin).
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * size, y: (1 - y) * size) }
    let funnel = NSBezierPath()
    funnel.move(to: p(0.23, 0.27))
    funnel.line(to: p(0.77, 0.27))
    funnel.line(to: p(0.575, 0.52))
    funnel.line(to: p(0.575, 0.75))
    funnel.line(to: p(0.425, 0.75))
    funnel.line(to: p(0.425, 0.52))
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
