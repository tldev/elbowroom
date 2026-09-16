#!/usr/bin/env swift
// App icon: three disk strata on a graphite plate, one cache-green tile.
// Run: swift Scripts/genicon.swift
import AppKit

let out = URL(fileURLWithPath: "Assets/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let plate = color("#1F1F22")
let bright = color("#F5F5F7")
let mid = color("#98989D")
let dim = color("#6E6E73")
let green = color("#2FB454")

func draw(px: Int) -> NSBitmapImageRep {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let inset = s * 0.045
    let plateRect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let platePath = NSBezierPath(roundedRect: plateRect, xRadius: s * 0.21, yRadius: s * 0.21)
    plate.setFill()
    platePath.fill()
    platePath.addClip()

    // Three strata bars + the cache tile, centered.
    let barH = s * 0.088
    let gap = s * 0.062
    let left = s * 0.24
    let full = s * 0.52
    let radius = barH / 2
    let blockH = barH * 3 + gap * 2
    let top = (s - blockH) / 2 + blockH - barH  // draw from top bar down (flipped coords)

    func bar(_ y: CGFloat, width: CGFloat, fill: NSColor) {
        let p = NSBezierPath(roundedRect: NSRect(x: left, y: y, width: width, height: barH), xRadius: radius, yRadius: radius)
        fill.setFill()
        p.fill()
    }
    bar(top, width: full, fill: bright)
    bar(top - barH - gap, width: full * 0.72, fill: mid)
    bar(top - 2 * (barH + gap), width: full * 0.38, fill: dim)
    // Cache-green tile aligned with the bottom bar's row end.
    let tile = NSBezierPath(roundedRect: NSRect(
        x: left + full * 0.38 + gap, y: top - 2 * (barH + gap), width: barH, height: barH
    ), xRadius: radius * 0.7, yRadius: radius * 0.7)
    green.setFill()
    tile.fill()
    return rep
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
    ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    let rep = draw(px: px)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", out.path, "-o", "Assets/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote Assets/AppIcon.icns" : "iconutil failed")
