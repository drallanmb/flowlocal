import AppKit
import ApplicationServices

/// Reads the text currently selected in the focused app.
/// Accessibility first (no side effects); Cmd+C as a fallback for apps that don't expose it (many Electron/web apps).
enum SelectionReader {
    static func read() -> String {
        if let s = viaAccessibility(), !s.isEmpty { return s }
        return viaCopy()
    }

    private static func viaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success else { return nil }
        return selected as? String
    }

    /// Copies the selection, reads it, then puts the user's clipboard back. Blocks up to ~0.3 s.
    private static func viaCopy() -> String {
        let pb = NSPasteboard.general
        let saved = TextInserter.snapshot(pb)
        pb.clearContents()
        let marker = pb.changeCount

        TextInserter.postCmd(TextInserter.cKey)
        let deadline = Date().addingTimeInterval(0.3)
        while pb.changeCount == marker && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }

        let text = pb.changeCount != marker ? (pb.string(forType: .string) ?? "") : ""
        TextInserter.restore(saved, to: pb)
        return text
    }
}
