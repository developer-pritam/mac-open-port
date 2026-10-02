// Icon designs for PortBar: full-colour app icons and monochrome menu bar glyphs.
// Shared by scripts/preview-icons.swift (comparison sheet) and scripts/make-icon.swift (.icns export).
import AppKit

// MARK: - Helpers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedPolygon(_ pts: [NSPoint], radius: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let last = pts[pts.count - 1]
    p.move(to: NSPoint(x: (last.x + pts[0].x) / 2, y: (last.y + pts[0].y) / 2))
    for i in pts.indices { p.appendArc(from: pts[i], to: pts[(i + 1) % pts.count], radius: radius) }
    p.close()
    return p
}

func glow(_ center: NSPoint, _ radius: CGFloat, _ color: NSColor) {
    NSGradient(colors: [color, color.withAlphaComponent(0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func withState(_ body: () -> Void) {
    NSGraphicsContext.current!.saveGraphicsState()
    body()
    NSGraphicsContext.current!.restoreGraphicsState()
}

/// The standard macOS icon tile (inset from the canvas, with a soft drop shadow). Contents are clipped to it.
func tile(_ canvas: NSRect, fill: () -> Void) {
    let t = canvas.insetBy(dx: canvas.width * 0.098, dy: canvas.width * 0.098)
    let path = NSBezierPath(roundedRect: t, xRadius: t.width * 0.225, yRadius: t.width * 0.225)
    withState {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
        shadow.shadowBlurRadius = canvas.width * 0.03
        shadow.shadowOffset = NSSize(width: 0, height: -canvas.width * 0.012)
        shadow.set()
        NSColor.black.setFill()
        path.fill()
    }
    withState {
        path.addClip()
        fill()
    }
    // Light-catching edge.
    withState {
        path.addClip()
        let edge = NSBezierPath(roundedRect: t.insetBy(dx: 0.5, dy: 0.5), xRadius: t.width * 0.225, yRadius: t.width * 0.225)
        edge.lineWidth = max(1, canvas.width * 0.004)
        NSColor(white: 1, alpha: 0.28).setStroke()
        edge.stroke()
    }
}

func tileRect(_ canvas: NSRect) -> NSRect { canvas.insetBy(dx: canvas.width * 0.098, dy: canvas.width * 0.098) }

/// Frosted glass slab: translucent fill, soft top sheen, and a top-lit gradient rim.
func glassSlab(_ r: NSRect, radius: CGFloat, fill: CGFloat = 0.16, light: Bool = false) {
    let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    withState {
        let s = NSShadow()
        s.shadowColor = NSColor(white: 0, alpha: light ? 0.12 : 0.25)
        s.shadowBlurRadius = r.width * 0.06
        s.shadowOffset = NSSize(width: 0, height: -r.width * 0.02)
        s.set()
        NSColor(white: 1, alpha: fill).setFill()
        p.fill()
    }
    withState {
        p.addClip()
        NSGradient(colors: [NSColor(white: 1, alpha: light ? 0.5 : 0.2), NSColor(white: 1, alpha: 0)])!
            .draw(in: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2), angle: -90)
    }
    let width = max(1, min(r.width, r.height) * 0.025)
    let rim = NSBezierPath(cgPath: p.cgPath.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1))
    withState {
        rim.addClip()
        NSGradient(colors: [NSColor(white: 1, alpha: 0.85), NSColor(white: 1, alpha: 0.1)])!.draw(in: r, angle: -90)
    }
}

// MARK: - RJ45 socket (shared by two designs)

func socketPath(_ b: NSRect) -> NSBezierPath {
    let nw = b.width * 0.36, nh = b.height * 0.24
    return roundedPolygon([
        NSPoint(x: b.minX, y: b.minY + nh), NSPoint(x: b.midX - nw / 2, y: b.minY + nh),
        NSPoint(x: b.midX - nw / 2, y: b.minY), NSPoint(x: b.midX + nw / 2, y: b.minY),
        NSPoint(x: b.midX + nw / 2, y: b.minY + nh), NSPoint(x: b.maxX, y: b.minY + nh),
        NSPoint(x: b.maxX, y: b.maxY), NSPoint(x: b.minX, y: b.maxY),
    ], radius: b.width * 0.06)
}

func drawSocket(_ b: NSRect, dark: Bool) {
    let hole = socketPath(b)
    withState {
        hole.addClip()
        NSGradient(colors: [rgb(0x020617), rgb(0x1E293B)])!.draw(in: b, angle: 90)
        // Gold contacts along the top.
        let n = 8
        let span = b.width * 0.66, w = b.width * 0.042, h = b.height * 0.30
        for i in 0..<n {
            let x = b.midX - span / 2 + CGFloat(i) * (span - w) / CGFloat(n - 1)
            let c = NSRect(x: x, y: b.maxY - h - b.height * 0.06, width: w, height: h)
            NSGradient(colors: [rgb(0xFDE68A), rgb(0xD97706)])!.draw(in: NSBezierPath(roundedRect: c, xRadius: w / 2, yRadius: w / 2), angle: -90)
        }
        // Inner shadow at the top lip.
        NSGradient(colors: [NSColor(white: 0, alpha: 0.6), NSColor(white: 0, alpha: 0)])!
            .draw(in: NSRect(x: b.minX, y: b.maxY - b.height * 0.12, width: b.width, height: b.height * 0.12), angle: -90)
    }
    hole.lineWidth = max(1, b.width * 0.018)
    NSColor(white: dark ? 1 : 0, alpha: dark ? 0.25 : 0.15).setStroke()
    hole.stroke()
}

func drawLEDs(_ b: NSRect) {
    let r = b.width * 0.055
    for (x, color) in [(b.minX + b.width * 0.1, rgb(0x4ADE80)), (b.maxX - b.width * 0.1, rgb(0xFBBF24))] {
        let c = NSPoint(x: x, y: b.maxY + b.height * 0.22)
        glow(c, r * 3.2, color.withAlphaComponent(0.55))
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        NSColor(white: 1, alpha: 0.7).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.45, y: c.y, width: r * 0.6, height: r * 0.5)).fill()
    }
}

// MARK: - Designs

struct IconDesign {
    let name: String
    let note: String
    let icon: (NSRect) -> Void
    /// Monochrome menu bar glyph drawn into an 18×18pt box.
    let glyph: (NSRect, NSColor) -> Void
}

let socketGlyph: (NSRect, NSColor) -> Void = { r, color in
    let b = NSRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.18, width: r.width * 0.76, height: r.height * 0.62)
    let outer = socketPath(b)
    let inset = r.width * 0.11
    let inner = socketPath(b.insetBy(dx: inset, dy: inset))
    outer.append(inner.reversed)
    color.setFill()
    outer.fill()
    // Contacts.
    let span = b.width * 0.42, w = r.width * 0.06
    for i in 0..<4 {
        let x = b.midX - span / 2 + CGFloat(i) * (span - w) / 3
        NSRect(x: x, y: b.maxY - inset - r.height * 0.16, width: w, height: r.height * 0.16).fill()
    }
}

let designs: [IconDesign] = [
    IconDesign(name: "Glass Socket", note: "Ethernet port on frosted glass, link LEDs on — violet") { canvas in
        tile(canvas) {
            let t = tileRect(canvas)
            NSGradient(colors: [rgb(0x312E81), rgb(0x6D28D9)])!.draw(in: t, angle: -60)
            glow(NSPoint(x: t.maxX - t.width * 0.15, y: t.minY + t.height * 0.15), t.width * 0.6, rgb(0xEC4899, 0.75))
            glow(NSPoint(x: t.minX + t.width * 0.1, y: t.maxY - t.height * 0.1), t.width * 0.5, rgb(0x22D3EE, 0.55))
            let plate = t.insetBy(dx: t.width * 0.14, dy: t.width * 0.17)
            glassSlab(plate, radius: plate.width * 0.16)
            let s = NSRect(x: plate.midX - plate.width * 0.34, y: plate.minY + plate.height * 0.17, width: plate.width * 0.68, height: plate.height * 0.5)
            drawSocket(s, dark: true)
            drawLEDs(s)
        }
    } glyph: { socketGlyph($0, $1) },

    IconDesign(name: "Glass Socket — Light", note: "Same idea, airy white glass with pastel blobs") { canvas in
        tile(canvas) {
            let t = tileRect(canvas)
            NSGradient(colors: [rgb(0xF8FAFC), rgb(0xE0E7FF)])!.draw(in: t, angle: -60)
            glow(NSPoint(x: t.maxX - t.width * 0.12, y: t.minY + t.height * 0.2), t.width * 0.6, rgb(0x818CF8, 0.7))
            glow(NSPoint(x: t.minX + t.width * 0.12, y: t.maxY - t.height * 0.15), t.width * 0.55, rgb(0x5EEAD4, 0.7))
            glow(NSPoint(x: t.minX + t.width * 0.2, y: t.minY + t.height * 0.1), t.width * 0.4, rgb(0xF9A8D4, 0.6))
            let plate = t.insetBy(dx: t.width * 0.14, dy: t.width * 0.17)
            glassSlab(plate, radius: plate.width * 0.16, fill: 0.45, light: true)
            let s = NSRect(x: plate.midX - plate.width * 0.34, y: plate.minY + plate.height * 0.17, width: plate.width * 0.68, height: plate.height * 0.5)
            drawSocket(s, dark: false)
            drawLEDs(s)
        }
    } glyph: { socketGlyph($0, $1) },

    IconDesign(name: "Radar", note: "Sonar sweep picking up live services as glowing blips") { canvas in
        tile(canvas) {
            let t = tileRect(canvas)
            NSGradient(colors: [rgb(0x1E293B), rgb(0x020617)])!
                .draw(fromCenter: NSPoint(x: t.midX, y: t.midY), radius: 0, toCenter: NSPoint(x: t.midX, y: t.midY), radius: t.width * 0.75, options: [])
            let c = NSPoint(x: t.midX, y: t.midY)
            let teal = rgb(0x2DD4BF)
            // Sweep wedge: many thin slices fading out behind the leading edge.
            let maxR = t.width * 0.40
            for i in 0..<60 {
                let a0 = 40 + CGFloat(i)
                let wedge = NSBezierPath()
                wedge.move(to: c)
                wedge.appendArc(withCenter: c, radius: maxR, startAngle: a0, endAngle: a0 + 1.2)
                wedge.close()
                teal.withAlphaComponent(0.42 * CGFloat(i) / 60).setFill()
                wedge.fill()
            }
            for (i, f) in [0.14, 0.27, 0.40].enumerated() {
                let rr = t.width * CGFloat(f)
                let ring = NSBezierPath(ovalIn: NSRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
                ring.lineWidth = t.width * 0.012
                teal.withAlphaComponent(0.65 - CGFloat(i) * 0.15).setStroke()
                ring.stroke()
            }
            // Leading edge of the sweep.
            let edge = NSBezierPath()
            edge.move(to: c)
            edge.line(to: NSPoint(x: c.x + maxR * cos(101 * .pi / 180), y: c.y + maxR * sin(101 * .pi / 180)))
            edge.lineWidth = t.width * 0.014
            edge.lineCapStyle = .round
            teal.setStroke()
            edge.stroke()
            for (p, color) in [((0.70, 0.66), rgb(0x4ADE80)), ((0.30, 0.36), rgb(0xC084FC)), ((0.64, 0.27), rgb(0xFB923C))] {
                let pt = NSPoint(x: t.minX + t.width * CGFloat(p.0), y: t.minY + t.height * CGFloat(p.1))
                glow(pt, t.width * 0.09, color.withAlphaComponent(0.7))
                let r = t.width * 0.03
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)).fill()
            }
            glow(c, t.width * 0.06, teal.withAlphaComponent(0.8))
            NSColor.white.setFill()
            let cr = t.width * 0.022
            NSBezierPath(ovalIn: NSRect(x: c.x - cr, y: c.y - cr, width: cr * 2, height: cr * 2)).fill()
            NSGradient(colors: [NSColor(white: 1, alpha: 0.14), NSColor(white: 1, alpha: 0)])!
                .draw(in: NSRect(x: t.minX, y: t.midY, width: t.width, height: t.height / 2), angle: -90)
        }
    } glyph: { r, color in
        let c = NSPoint(x: r.midX, y: r.midY)
        color.setFill()
        color.setStroke()
        let d = r.width * 0.16
        NSBezierPath(ovalIn: NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)).fill()
        for (rad, start, end) in [(r.width * 0.25, 0.0, 360.0), (r.width * 0.42, 30.0, 330.0)] {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: rad, startAngle: CGFloat(start), endAngle: CGFloat(end))
            arc.lineWidth = r.width * 0.09
            arc.lineCapStyle = .round
            arc.stroke()
        }
        // Blip in the gap of the outer ring.
        let b = r.width * 0.15
        NSBezierPath(ovalIn: NSRect(x: c.x + r.width * 0.42 - b / 2, y: c.y - b / 2, width: b, height: b)).fill()
    },

    IconDesign(name: "Terminal :port", note: "Dev-tool look — a glass terminal window showing :3000") { canvas in
        tile(canvas) {
            let t = tileRect(canvas)
            NSGradient(colors: [rgb(0x0EA5E9), rgb(0x8B5CF6)])!.draw(in: t, angle: -55)
            glow(NSPoint(x: t.maxX, y: t.minY), t.width * 0.6, rgb(0xF472B6, 0.7))
            let win = t.insetBy(dx: t.width * 0.12, dy: t.width * 0.2)
            glassSlab(win, radius: win.width * 0.1, fill: 0.14)
            // Title bar dots.
            let dot = win.width * 0.055
            for (i, color) in [rgb(0xFF5F57), rgb(0xFEBC2E), rgb(0x28C840)].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: win.minX + win.width * 0.08 + CGFloat(i) * dot * 1.7, y: win.maxY - win.height * 0.17, width: dot, height: dot)).fill()
            }
            let font = NSFont.monospacedSystemFont(ofSize: win.width * 0.25, weight: .heavy)
            let text = NSMutableAttributedString(string: ":", attributes: [.font: font, .foregroundColor: rgb(0xF9A8D4)])
            text.append(NSAttributedString(string: "3000", attributes: [.font: font, .foregroundColor: NSColor.white]))
            let size = text.size()
            let origin = NSPoint(x: win.midX - (size.width + win.width * 0.08) / 2, y: win.minY + win.height * 0.24)
            withState {
                let s = NSShadow()
                s.shadowColor = rgb(0x1E1B4B, 0.5)
                s.shadowBlurRadius = win.width * 0.03
                s.set()
                text.draw(at: origin)
            }
            // Cursor block.
            rgb(0x4ADE80).setFill()
            NSRect(x: origin.x + size.width + win.width * 0.02, y: origin.y + size.height * 0.2, width: win.width * 0.06, height: size.height * 0.62).fill()
        }
    } glyph: { r, color in
        let b = r.insetBy(dx: r.width * 0.06, dy: r.height * 0.14)
        let frame = NSBezierPath(roundedRect: b, xRadius: r.width * 0.16, yRadius: r.width * 0.16)
        frame.lineWidth = r.width * 0.09
        color.setStroke()
        color.setFill()
        frame.stroke()
        // Colon + cursor.
        let d = r.width * 0.13
        for y in [b.midY + d * 0.55, b.midY - d * 1.55] {
            NSBezierPath(ovalIn: NSRect(x: b.minX + b.width * 0.24, y: y, width: d, height: d)).fill()
        }
        NSBezierPath(roundedRect: NSRect(x: b.minX + b.width * 0.5, y: b.midY - d * 1.5, width: b.width * 0.26, height: d * 0.95), xRadius: d * 0.3, yRadius: d * 0.3).fill()
    },

    IconDesign(name: "Service Lights", note: "Stacked glass server units with status LEDs (running / stopped)") { canvas in
        tile(canvas) {
            let t = tileRect(canvas)
            NSGradient(colors: [rgb(0x0F766E), rgb(0x1D4ED8)])!.draw(in: t, angle: -60)
            glow(NSPoint(x: t.minX + t.width * 0.1, y: t.maxY - t.height * 0.1), t.width * 0.55, rgb(0x34D399, 0.6))
            glow(NSPoint(x: t.maxX - t.width * 0.1, y: t.minY + t.height * 0.15), t.width * 0.55, rgb(0xA855F7, 0.7))
            let w = t.width * 0.66, h = t.height * 0.17, gap = t.height * 0.055
            let total = h * 3 + gap * 2
            for (i, led) in [rgb(0x4ADE80), rgb(0x4ADE80), rgb(0xF87171)].enumerated() {
                let y = t.midY + total / 2 - CGFloat(i + 1) * h - CGFloat(i) * gap
                let pill = NSRect(x: t.midX - w / 2, y: y, width: w, height: h)
                glassSlab(pill, radius: h * 0.32, fill: 0.18)
                let c = NSPoint(x: pill.minX + h * 0.55, y: pill.midY)
                let r = h * 0.15
                glow(c, r * 3.4, led.withAlphaComponent(0.65))
                led.setFill()
                NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
                NSColor(white: 1, alpha: 0.75).setFill()
                let lh = h * 0.13
                NSBezierPath(roundedRect: NSRect(x: pill.minX + h * 1.05, y: pill.midY + lh * 0.4, width: w * 0.42, height: lh), xRadius: lh / 2, yRadius: lh / 2).fill()
                NSColor(white: 1, alpha: 0.4).setFill()
                NSBezierPath(roundedRect: NSRect(x: pill.minX + h * 1.05, y: pill.midY - lh * 1.5, width: w * 0.26, height: lh), xRadius: lh / 2, yRadius: lh / 2).fill()
            }
        }
    } glyph: { r, color in
        let w = r.width * 0.86, h = r.height * 0.24, gap = r.height * 0.08
        let total = h * 3 + gap * 2
        color.setStroke()
        color.setFill()
        for i in 0..<3 {
            let y = r.midY + total / 2 - CGFloat(i + 1) * h - CGFloat(i) * gap
            let unit = NSRect(x: r.midX - w / 2, y: y, width: w, height: h)
            let p = NSBezierPath(roundedRect: unit.insetBy(dx: 0.6, dy: 0.6), xRadius: h * 0.35, yRadius: h * 0.35)
            p.lineWidth = r.width * 0.075
            p.stroke()
            let d = h * 0.42
            NSBezierPath(ovalIn: NSRect(x: unit.minX + h * 0.32, y: unit.midY - d / 2, width: d, height: d)).fill()
        }
    },
]
