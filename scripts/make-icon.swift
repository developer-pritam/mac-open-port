// Exports one design from IconDesigns.swift as Resources/AppIcon.icns plus the website icons in docs/assets.
// Run via scripts/make-icon.sh.
import AppKit

let chosen = "Terminal :port"
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let design = designs.first { $0.name == chosen }!

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// 1024px (512@2x) is left out on purpose: it doubles the .icns size for no visible gain in a menu bar app.
func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    design.icon(NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                   (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512")] {
    try! png(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out]
try! iconutil.run()
iconutil.waitUntilExit()
print("✓ \(out) (\(chosen))")

// Website icons.
let assets = URL(fileURLWithPath: "docs/assets")
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
for (px, name) in [(512, "icon.png"), (64, "favicon.png"), (180, "apple-touch-icon.png")] {
    try! png(px).write(to: assets.appendingPathComponent(name))
}
print("✓ docs/assets/{icon,favicon,apple-touch-icon}.png")
