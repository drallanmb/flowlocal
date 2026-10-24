import AppKit
import ApplicationServices

/// Inserts text into the focused app: clipboard swap + synthetic Cmd+V, then restores the clipboard.
enum TextInserter {
    private static let vKey: CGKeyCode = 9
    static let cKey: CGKeyCode = 8

    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)
        let ourChange = pb.changeCount

        postCmd(vKey)

        // Give the target app time to read the pasteboard before restoring it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // If something else wrote to the clipboard meanwhile, leave it alone.
            guard pb.changeCount == ourChange else { return }
            restore(saved, to: pb)
        }
    }

    /// Synthesises Cmd+<key> in the focused app.
    static func postCmd(_ key: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func snapshot(_ pb: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    static func restore(_ items: [[(NSPasteboard.PasteboardType, Data)]], to pb: NSPasteboard) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(restored)
    }
}
