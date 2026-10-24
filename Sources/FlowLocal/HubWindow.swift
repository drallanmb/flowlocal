import AppKit
import SwiftUI

enum HubPage: String, CaseIterable, Identifiable {
    case history, dictionary, snippets, style, scratchpad, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "Início"
        case .dictionary: return "Dicionário"
        case .snippets: return "Snippets"
        case .style: return "Estilo"
        case .scratchpad: return "Rascunho"
        case .settings: return "Configurações"
        }
    }

    var symbol: String {
        switch self {
        case .history: return "house"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .style: return "textformat"
        case .scratchpad: return "note.text"
        case .settings: return "gearshape"
        }
    }
}

final class HubNav: ObservableObject {
    static let shared = HubNav()
    @Published var page: HubPage = .history
}

/// The Hub: a regular window (with a Dock icon while open), like Wispr Flow's main window.
/// The app returns to menu-bar-only mode when it closes.
final class HubWindow: NSObject, NSWindowDelegate {
    static let shared = HubWindow()
    private var window: NSWindow?

    func show(page: HubPage? = nil) {
        if let page { HubNav.shared.page = page }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "FlowLocal"
            w.titlebarAppearsTransparent = true
            w.minSize = NSSize(width: 820, height: 520)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HubView().environmentObject(HubNav.shared))
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("FlowLocalHub")
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
