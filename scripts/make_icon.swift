import AppKit

// Renders the 1024px app icon: documents dropping from a glowing notch into a frosted shelf.
let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func withShadow(_ color: NSColor, blur: CGFloat, offset: NSSize = .zero, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

let cyan = rgb(0.38, 0.86, 1.0)
let violet = rgb(0.58, 0.42, 1.0)

// Tile
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tileShape = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
withShadow(rgb(0, 0, 0, 0.45), blur: 30, offset: NSSize(width: 0, height: -12)) {
    rgb(0, 0, 0).setFill()
    tileShape.fill()
}
NSGradient(colors: [rgb(0.17, 0.18, 0.40), rgb(0.09, 0.09, 0.22), rgb(0.04, 0.05, 0.12)])!.draw(in: tileShape, angle: -90)

NSGraphicsContext.saveGraphicsState()
tileShape.addClip()

// Light spilling down from the notch
let spill = NSGradient(colors: [cyan.withAlphaComponent(0.55), violet.withAlphaComponent(0.22), violet.withAlphaComponent(0)])!
spill.draw(fromCenter: NSPoint(x: 512, y: 860), radius: 0, toCenter: NSPoint(x: 512, y: 860), radius: 420, options: [])

// Notch with a glowing rim
let notch = NSBezierPath()
let nLeft: CGFloat = 392, nRight: CGFloat = 632, nBottom: CGFloat = 836, r: CGFloat = 40
notch.move(to: NSPoint(x: nLeft - 30, y: 930))
notch.line(to: NSPoint(x: nLeft, y: 930))
notch.line(to: NSPoint(x: nLeft, y: nBottom + r))
notch.appendArc(withCenter: NSPoint(x: nLeft + r, y: nBottom + r), radius: r, startAngle: 180, endAngle: 270)
notch.line(to: NSPoint(x: nRight - r, y: nBottom))
notch.appendArc(withCenter: NSPoint(x: nRight - r, y: nBottom + r), radius: r, startAngle: 270, endAngle: 360)
notch.line(to: NSPoint(x: nRight, y: 930))
notch.line(to: NSPoint(x: nRight + 30, y: 930))
notch.close()
let rim = NSBezierPath()
rim.move(to: NSPoint(x: nLeft, y: 924))
rim.line(to: NSPoint(x: nLeft, y: nBottom + r))
rim.appendArc(withCenter: NSPoint(x: nLeft + r, y: nBottom + r), radius: r, startAngle: 180, endAngle: 270)
rim.line(to: NSPoint(x: nRight - r, y: nBottom))
rim.appendArc(withCenter: NSPoint(x: nRight - r, y: nBottom + r), radius: r, startAngle: 270, endAngle: 360)
rim.line(to: NSPoint(x: nRight, y: 924))
rim.lineWidth = 7
rim.lineCapStyle = .round
for blur in [60.0, 28.0, 10.0] {
    withShadow(cyan, blur: blur) {
        cyan.setStroke()
        rim.stroke()
    }
}
rgb(0.86, 0.97, 1.0).setStroke()
rim.lineWidth = 4
rim.stroke()
rgb(0, 0, 0).setFill()
notch.fill()

// Documents
func card(center: NSPoint, angle: CGFloat, top: NSColor, bottom: NSColor, lines: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    t.rotate(byDegrees: angle)
    t.concat()
    let rect = NSRect(x: -112, y: -146, width: 224, height: 292)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30)
    withShadow(rgb(0, 0, 0, 0.45), blur: 24, offset: NSSize(width: 0, height: -10)) {
        top.setFill()
        shape.fill()
    }
    NSGradient(colors: [top, bottom])!.draw(in: shape, angle: -90)
    rgb(1, 1, 1, 0.5).setStroke()
    shape.lineWidth = 3
    shape.stroke()
    if lines {
        let ink = rgb(0.30, 0.34, 0.55, 0.55)
        ink.setFill()
        for (i, width) in [150.0, 170.0, 128.0, 160.0].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: -85, y: 92 - Double(i) * 42, width: width, height: 18), xRadius: 9, yRadius: 9).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}
card(center: NSPoint(x: 392, y: 470), angle: 13, top: rgb(0.45, 0.72, 1.0), bottom: rgb(0.22, 0.44, 0.96), lines: false)
card(center: NSPoint(x: 632, y: 470), angle: -13, top: rgb(0.74, 0.56, 1.0), bottom: rgb(0.47, 0.30, 0.92), lines: false)
card(center: NSPoint(x: 512, y: 505), angle: 0, top: rgb(1, 1, 1), bottom: rgb(0.88, 0.91, 1.0), lines: true)

// Frosted shelf front the documents sit in
let shelf = NSBezierPath(roundedRect: NSRect(x: 214, y: 218, width: 596, height: 214), xRadius: 64, yRadius: 64)
withShadow(rgb(0, 0, 0, 0.4), blur: 30, offset: NSSize(width: 0, height: -10)) {
    rgb(0.30, 0.34, 0.70, 0.75).setFill()
    shelf.fill()
}
NSGradient(colors: [rgb(0.62, 0.70, 1.0, 0.85), rgb(0.30, 0.30, 0.78, 0.92)])!.draw(in: shelf, angle: -90)
NSGraphicsContext.saveGraphicsState()
shelf.addClip()
NSGradient(colors: [rgb(1, 1, 1, 0.45), rgb(1, 1, 1, 0)])!.draw(in: NSRect(x: 214, y: 380, width: 596, height: 52), angle: -90)
NSGraphicsContext.restoreGraphicsState()
rgb(1, 1, 1, 0.55).setStroke()
shelf.lineWidth = 4
shelf.stroke()
// Slot in the shelf front
rgb(0.10, 0.10, 0.30, 0.55).setFill()
NSBezierPath(roundedRect: NSRect(x: 432, y: 300, width: 160, height: 22), xRadius: 11, yRadius: 11).fill()

NSGraphicsContext.restoreGraphicsState() // tile clip

// Subtle edge highlight on the tile
rgb(1, 1, 1, 0.12).setStroke()
let edge = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
edge.lineWidth = 3
edge.stroke()

_ = cg
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
