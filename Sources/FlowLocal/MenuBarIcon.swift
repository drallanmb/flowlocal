import AppKit

/// The FlowLocal mark for the menu bar and Hub: an "L" emitting sound waves, drawn as a template
/// image so macOS tints it for light/dark menu bars. `arcs` = 2 at rest, 3 while recording.
enum MenuBarIcon {
    static func image(arcs: Int, size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let u = size / 18   // artwork is designed on an 18 pt grid
            NSColor.black.setStroke()

            let l = NSBezierPath()
            l.move(to: NSPoint(x: 4 * u, y: 15.5 * u))
            l.line(to: NSPoint(x: 4 * u, y: 3.2 * u))
            l.line(to: NSPoint(x: 10.5 * u, y: 3.2 * u))
            l.lineWidth = 2.4 * u
            l.lineCapStyle = .round
            l.lineJoinStyle = .round
            l.stroke()

            let center = NSPoint(x: 6.1 * u, y: 5.3 * u)
            for (i, r) in [2.8, 5.4, 8.0].prefix(arcs).enumerated() {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: CGFloat(r) * u, startAngle: 5, endAngle: 85)
                arc.lineWidth = 1.6 * u
                arc.lineCapStyle = .round
                // Outer waves read as fading, without leaving the template's single-colour rule.
                NSColor.black.withAlphaComponent(1 - CGFloat(i) * 0.22).setStroke()
                arc.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
