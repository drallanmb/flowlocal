// Draws the FlowLocal app icon (original artwork): indigo squircle, an "L" emitting sound waves.
// Usage: swift scripts/make_icon.swift Resources/AppIcon.icns
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: artwork occupies ~82% of the canvas.
    let inset = s * 0.09
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.42, green: 0.36, blue: 0.98, alpha: 1),
                        NSColor(red: 0.10, green: 0.10, blue: 0.36, alpha: 1)])!.draw(in: path, angle: -60)

    // Soft top highlight.
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Mark: a bold "L" whose inner corner emits sound waves (three quarter-circle arcs).
    // Geometry is in unit coordinates of the artwork square, origin bottom-left.
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: body.minX + x * body.width, y: body.minY + y * body.height) }
    let stroke = body.width * 0.115
    let stemX: CGFloat = 0.30, footY: CGFloat = 0.27
    let top: CGFloat = 0.76, right: CGFloat = 0.62

    let l = NSBezierPath()
    l.move(to: pt(stemX, top))
    l.line(to: pt(stemX, footY))
    l.line(to: pt(right, footY))
    l.lineWidth = stroke
    l.lineCapStyle = .round
    l.lineJoinStyle = .round
    NSColor.white.setStroke()
    l.stroke()

    // Waves radiate from the L's inner corner into the open quadrant.
    // Centre sits in the L's concave corner, clear of both strokes, so the arcs never touch the letter.
    let clear = stroke / 2 + body.width * 0.035
    let c0 = pt(stemX, footY)
    let corner = NSPoint(x: c0.x + clear, y: c0.y + clear)
    let radii: [CGFloat] = [0.10, 0.20, 0.30]
    for (k, radius) in radii.enumerated() {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: corner, radius: radius * body.width, startAngle: 4, endAngle: 86)
        arc.lineWidth = stroke * 0.55
        arc.lineCapStyle = .round
        NSColor.white.withAlphaComponent(1.0 - CGFloat(k) * 0.3).setStroke()
        arc.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let tmp = NSTemporaryDirectory() + "FlowLocal.iconset"
try? FileManager.default.removeItem(atPath: tmp)
try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: URL(fileURLWithPath: "\(tmp)/icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: URL(fileURLWithPath: "\(tmp)/icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp, "-o", out]
try! p.run(); p.waitUntilExit()
print("wrote \(out) (status \(p.terminationStatus))")
