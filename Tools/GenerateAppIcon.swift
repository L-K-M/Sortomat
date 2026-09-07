#!/usr/bin/env swift
//
// GenerateAppIcon.swift — regenerate Sortomat's app icon natively on macOS.
//
// Fits the master artwork at media-sources/icon.png to Apple's macOS icon
// grid, exactly as Tools/generate_icon.py does. The committed PNGs are produced
// by the Python script, which needs nothing but the standard library and so
// runs on any box; use this on a Mac if you would rather go through AppKit.
//
// The geometry has to match the Python script: the body is 824 of a 1024
// canvas, centred, with a 185.4 corner radius — a fraction of the *body*, not
// of the canvas. An icon drawn edge to edge renders about a quarter larger than
// every neighbour in the Dock, because the system scales them all the same.
//
// Usage: swift Tools/GenerateAppIcon.swift [OUTPUT_APPICONSET_DIR] [SOURCE_PNG]
//
import AppKit

let ladder: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

// Apple's macOS icon grid, in points on a 1024 canvas.
let canvas: CGFloat = 1024
let bodySide: CGFloat = 824
let cornerRadius: CGFloat = 185.4

let arguments = Array(CommandLine.arguments.dropFirst())
let outDir = arguments.count > 0
    ? arguments[0]
    : "Sortomat/Resources/Assets.xcassets/AppIcon.appiconset"
let sourcePath = arguments.count > 1 ? arguments[1] : "media-sources/icon.png"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("GenerateAppIcon: \(message)\n".utf8))
    exit(1)
}

guard let artwork = NSImage(contentsOfFile: sourcePath) else {
    fail("cannot read artwork at \(sourcePath)")
}
guard artwork.size.width == artwork.size.height else {
    fail("the artwork must be square (got \(artwork.size))")
}

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // The artwork is photographic and every size below 512 is a real
    // downscale: at the default interpolation its edges alias into noise.
    context.imageInterpolation = .high

    let scale = size / canvas
    let body = bodySide * scale
    let origin = (size - body) / 2
    let rect = NSRect(x: origin, y: origin, width: body, height: body)
    let radius = cornerRadius * scale
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    // The artwork is square and edge-to-edge, so it *is* the tile: it fills
    // the body rather than sitting on the canvas.
    artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

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
