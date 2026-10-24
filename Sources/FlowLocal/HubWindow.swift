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

/// Standard menu bar for the Hub. Without an Edit menu, ⌘V/⌘C/⌘Z do nothing in text fields: AppKit routes those
/// key equivalents through the main menu, and a menu-less app has none. (This also broke dictating into the Hub itself.)
enum MainMenu {
    static func install() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Sobre o FlowLocal", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Ocultar FlowLocal", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Sair do FlowLocal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, to: main, title: "FlowLocal")

        let edit = NSMenu(title: "Editar")
        edit.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Selecionar tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main, title: "Editar")

        let window = NSMenu(title: "Janela")
        window.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Fechar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, to: main, title: "Janela")
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    private static func add(_ submenu: NSMenu, to main: NSMenu, title: String) {
        submenu.title = title
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
