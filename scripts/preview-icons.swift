// Renders a comparison sheet of every design in IconDesigns.swift and opens it.
// Usage: ./scripts/make-icon.sh preview
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-preview.png"
let rowH: CGFloat = 250, W: CGFloat = 1180, header: CGFloat = 70
let H = header + rowH * CGFloat(designs.count)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * 2), pixelsHigh: Int(H * 2), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)  // draw in points, render at 2x
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

rgb(0xF4F4F6).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

func text(_ s: String, _ p: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = rgb(0x111827)) {
    (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

func render(_ design: IconDesign, px: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px), flipped: false) { r in design.icon(r); return true }
    return img
}

func menuBar(_ design: IconDesign, in bar: NSRect, dark: Bool) {
    // Wallpaper peeking through the translucent bar.
    let wall = dark ? [rgb(0x1E1B4B), rgb(0x0F172A)] : [rgb(0xBFDBFE), rgb(0xFBCFE8)]
    let shape = NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10)
    withState {
        shape.addClip()
        NSGradient(colors: wall)!.draw(in: bar, angle: 0)
        (dark ? NSColor(white: 0.08, alpha: 0.55) : NSColor(white: 1, alpha: 0.55)).setFill()
        NSRect(x: bar.minX, y: bar.maxY - 26, width: bar.width, height: 26).fill()
    }
    let fg = dark ? NSColor.white : NSColor.black
    let y = bar.maxY - 26
    var x = bar.maxX - 12
    let clock = "Thu 2 Oct  10:42" as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: fg]
    x -= clock.size(withAttributes: attrs).width
    clock.draw(at: NSPoint(x: x, y: y + 4.5), withAttributes: attrs)
    for name in ["battery.75percent", "wifi"] {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular).applying(.init(paletteColors: [fg])))!
        x -= img.size.width + 14
        img.draw(in: NSRect(x: x, y: y + (26 - img.size.height) / 2, width: img.size.width, height: img.size.height))
    }
    // Our item: glyph + count.
    let count = "12" as NSString
    let cAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium), .foregroundColor: fg]
    x -= count.size(withAttributes: cAttrs).width + 16
    count.draw(at: NSPoint(x: x, y: y + 4.5), withAttributes: cAttrs)
    x -= 23
    design.glyph(NSRect(x: x, y: y + 4, width: 18, height: 18), fg)
}

text("PortBar — icon options", NSPoint(x: 32, y: H - 44), size: 22, weight: .bold)
text("Each row: large · real sizes 128 / 64 / 32 / 16 px · menu bar light & dark", NSPoint(x: 330, y: H - 40), size: 13, color: rgb(0x6B7280))

for (i, d) in designs.enumerated() {
    let top = H - header - CGFloat(i) * rowH
    let rowRect = NSRect(x: 16, y: top - rowH + 10, width: W - 32, height: rowH - 20)
    rgb(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: rowRect, xRadius: 18, yRadius: 18).fill()

    text("\(i + 1)", NSPoint(x: 36, y: top - 46), size: 26, weight: .heavy, color: rgb(0xD1D5DB))
    text(d.name, NSPoint(x: 36, y: top - 76), size: 16, weight: .semibold)
    let note = d.note as NSString
    note.draw(in: NSRect(x: 36, y: top - 160, width: 160, height: 80),
              withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: rgb(0x6B7280)])

    // Large.
    render(d, px: 200).draw(in: NSRect(x: 200, y: top - 225, width: 200, height: 200))
    // Real sizes (bottom-aligned, drawn 1pt = 1px of the target size on a 1x screen).
    var x: CGFloat = 420
    for s in [128, 64, 32, 16] {
        let sz = CGFloat(s)
        render(d, px: s).draw(in: NSRect(x: x, y: top - 190, width: sz, height: sz))
        text("\(s)", NSPoint(x: x + sz / 2 - 8, y: top - 212), size: 11, color: rgb(0x9CA3AF))
        x += sz + 22
    }
    // Menu bars.
    menuBar(d, in: NSRect(x: 760, y: top - 100, width: 390, height: 72), dark: false)
    menuBar(d, in: NSRect(x: 760, y: top - 190, width: 390, height: 72), dark: true)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("✓ \(out)")
