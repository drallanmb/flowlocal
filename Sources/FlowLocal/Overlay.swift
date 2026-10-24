import AppKit

/// Small floating pill near the bottom of the screen showing the dictation state.
final class Overlay {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 36),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let bg = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 18
        bg.layer?.masksToBounds = true
        panel.contentView = bg

        dot.frame = NSRect(x: 14, y: 12, width: 12, height: 12)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 6
        bg.addSubview(dot)

        label.frame = NSRect(x: 34, y: 8, width: 148, height: 20)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        bg.addSubview(label)
    }

    func show(_ text: String, color: NSColor) {
        DispatchQueue.main.async {
            self.label.stringValue = text
            self.dot.layer?.backgroundColor = color.cgColor
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                self.panel.setFrameOrigin(NSPoint(x: f.midX - self.panel.frame.width / 2, y: f.minY + 48))
            }
            self.panel.orderFrontRegardless()
        }
    }

    func setLevel(_ level: Float) {
        DispatchQueue.main.async { self.dot.layer?.opacity = 0.45 + level * 0.55 }
    }

    func hide(after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.panel.orderOut(nil) }
    }
}
