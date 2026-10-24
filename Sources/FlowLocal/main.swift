import AppKit
import SwiftUI
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let whisper = WhisperServer()
    private let polisher = LLMPolisher()
    private let overlay = Overlay()
    private var statusLine = "Iniciando…"
    /// App that had focus when the hotkey went down (decides the tone, and is logged in history).
    private var targetApp: NSRunningApplication?
    private var mode: HotkeyMonitor.Mode = .dictation
    /// Text selected when the command key went down (empty = write new text from the instruction).
    private var commandSelection = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        setIcon(active: false)
        rebuildMenu()
        requestPermissions()

        recorder.onLevel = { [weak self] in self?.overlay.setLevel($0) }
        hotkey.onPress = { [weak self] in self?.beginDictation($0) }
        hotkey.onRelease = { [weak self] _ in self?.endDictation() }
        hotkey.start()
        if Settings.llmEnabled || Settings.commandHotkey != nil { polisher.prepare() }
        startWhisper()

        // The Hub edits UserDefaults directly; keep the menu and background services in sync.
        let nc = NotificationCenter.default
        nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuildMenu() }
        nc.addObserver(forName: .restartWhisper, object: nil, queue: .main) { [weak self] _ in self?.startWhisper() }
        nc.addObserver(forName: .reloadLLM, object: nil, queue: .main) { [weak self] _ in
            if Settings.llmEnabled || Settings.commandHotkey != nil { self?.polisher.prepare() }
        }

        HubWindow.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) { whisper.stop(); polisher.stop() }

    /// Clicking the Dock icon / relaunching reopens the Hub, as in Wispr Flow.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        HubWindow.shared.show()
        return true
    }

    private func startWhisper() {
        setStatus("Carregando modelo…")
        whisper.start { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success: self?.setStatus("Pronto — segure \(Settings.hotkey.title)")
                case .failure(let e): self?.setStatus("Erro: \(e.localizedDescription)")
                }
            }
        }
    }

    // MARK: Dictation flow

    private func beginDictation(_ mode: HotkeyMonitor.Mode) {
        guard whisper.isReady else { overlay.show("Carregando modelo…", color: .systemOrange); overlay.hide(after: 1.5); return }
        do {
            // Our own windows (Hub) count too: dictating into the Scratchpad is a supported use.
            targetApp = NSWorkspace.shared.frontmostApplication
            self.mode = mode
            // The selection must be read before recording: the target app still has focus and its selection intact.
            commandSelection = mode == .command ? SelectionReader.read() : ""
            try recorder.start()
            setIcon(active: true)
            if mode == .command {
                overlay.show(commandSelection.isEmpty ? "Comando: escrever…" : "Comando: editar…", color: .systemTeal)
            } else {
                overlay.show("Ouvindo…", color: .systemRed)
            }
        } catch {
            overlay.show("Sem microfone", color: .systemOrange); overlay.hide(after: 2)
        }
    }

    private func endDictation() {
        guard recorder.isRecording else { return }
        let samples = recorder.stop()
        setIcon(active: false)

        // Ignore accidental taps (< 0.4 s of audio).
        guard samples.count > 6_400 else { overlay.hide(); return }
        overlay.show("Transcrevendo…", color: .systemBlue)

        let wav = AudioRecorder.wav(from: samples)
        let language = Settings.language
        let hint = TextCleaner.promptHint()
        let seconds = Double(samples.count) / 16_000
        let appName = targetApp?.localizedName ?? ""
        let tone = AppCategory.of(bundleID: targetApp?.bundleIdentifier).tone

        if mode == .command {
            runCommand(wav: wav, language: language, hint: hint, seconds: seconds, appName: appName)
            return
        }

        Task {
            do {
                let raw = try await whisper.transcribe(wav: wav, language: language, prompt: hint)
                let (expanded, usedSnippet) = SnippetStore.apply(to: TextCleaner.clean(raw))
                var polished = expanded
                // Snippet expansions are verbatim text the user wrote; keep the LLM away from them.
                if Settings.llmEnabled, !expanded.isEmpty, !usedSnippet {
                    overlay.show("Polindo…", color: .systemPurple)
                    polished = await polisher.polish(expanded, dictionaryTerms: TextCleaner.dictionaryTerms(), tone: tone)
                }
                let text = polished
                await MainActor.run {
                    if text.isEmpty {
                        overlay.show("Nada detectado", color: .systemGray); overlay.hide(after: 1.2)
                    } else {
                        TextInserter.insert(text)
                        overlay.hide()
                        History.append(raw: raw, text: text, seconds: seconds, app: appName)
                    }
                }
            } catch {
                await MainActor.run {
                    overlay.show("Falha: \(error.localizedDescription)", color: .systemRed)
                    overlay.hide(after: 3)
                }
            }
        }
    }

    /// Command mode: the transcript is an instruction applied to the selection (or a prompt, with no selection).
    private func runCommand(wav: Data, language: String, hint: String, seconds: Double, appName: String) {
        let selection = commandSelection
        let target = targetApp
        Task {
            do {
                let spoken = try await whisper.transcribe(wav: wav, language: language, prompt: hint)
                let instruction = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instruction.isEmpty else {
                    await MainActor.run { overlay.show("Nada detectado", color: .systemGray); overlay.hide(after: 1.2) }
                    return
                }
                overlay.show(selection.isEmpty ? "Escrevendo…" : "Reescrevendo…", color: .systemTeal)
                let result = try await polisher.transform(selected: selection, instruction: instruction,
                                                          dictionaryTerms: TextCleaner.dictionaryTerms())
                await MainActor.run {
                    History.append(raw: instruction, text: result, seconds: seconds, app: appName, kind: "command")
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == target?.processIdentifier {
                        // The selection is still active in the target, so pasting replaces it (Cmd+Z undoes).
                        TextInserter.insert(result)
                        overlay.hide()
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                        overlay.show("Foco mudou — resultado copiado", color: .systemOrange)
                        overlay.hide(after: 3)
                    }
                }
            } catch {
                await MainActor.run {
                    overlay.show("Falha: \(error.localizedDescription)", color: .systemRed)
                    overlay.hide(after: 3)
                }
            }
        }
    }

    // MARK: Permissions

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            setStatus("Conceda Acessibilidade em Ajustes do Sistema e reabra o app")
        }
        CGRequestListenEventAccess()
    }

    // MARK: Menu (compact; the Hub holds the full settings)

    private func setIcon(active: Bool) {
        DispatchQueue.main.async {
            let button = self.statusItem.button
            button?.image = MenuBarIcon.image(arcs: active ? 3 : 2)
            button?.image?.accessibilityDescription = "FlowLocal"
        }
    }

    private func setStatus(_ s: String) {
        statusLine = s
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let hub = NSMenuItem(title: "Abrir Hub", action: #selector(openHub), keyEquivalent: ",")
        hub.target = self
        menu.addItem(hub)
        for page in [HubPage.history, .dictionary, .snippets, .style] {
            let item = NSMenuItem(title: page.title, action: #selector(openHubPage(_:)), keyEquivalent: "")
            item.representedObject = page.rawValue
            item.target = self
            item.indentationLevel = 1
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let llm = NSMenuItem(title: "Polimento por LLM", action: #selector(toggleLLM), keyEquivalent: "")
        llm.state = Settings.llmEnabled ? .on : .off
        llm.target = self
        menu.addItem(llm)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openHub() { HubWindow.shared.show() }

    @objc private func openHubPage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let page = HubPage(rawValue: raw) {
            HubWindow.shared.show(page: page)
        }
    }

    @objc private func toggleLLM() {
        Settings.llmEnabled.toggle()
        if Settings.llmEnabled { polisher.prepare() }
        rebuildMenu()
    }
}

/// `FlowLocal --snapshot <dir>` renders every Hub page to PNG offscreen and exits (visual check without screen-recording permission).
func snapshotHub(to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for page in HubPage.allCases {
        HubNav.shared.page = page
        let host = NSHostingView(rootView: HubView().environmentObject(HubNav.shared))
        let win = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 980, height: 660), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(page.rawValue).png"))
        }
        win.orderOut(nil)
    }
    // Menu bar icon states, at 18 pt (as shipped) and enlarged, on light and dark bars.
    let sheet = NSImage(size: NSSize(width: 480, height: 150), flipped: false) { rect in
        for (i, dark) in [false, true].enumerated() {
            let bg = NSRect(x: CGFloat(i) * 240, y: 0, width: 240, height: 150)
            (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill(); bg.fill()
            for (k, arcs) in [2, 3].enumerated() {
                let tint = dark ? NSColor.white : NSColor.black
                let icon = MenuBarIcon.image(arcs: arcs, size: 100)
                icon.lockFocus()
                tint.set(); NSRect(x: 0, y: 0, width: 100, height: 100).fill(using: .sourceIn)
                icon.unlockFocus()
                icon.draw(in: NSRect(x: bg.minX + 15 + CGFloat(k) * 110, y: 40, width: 100, height: 100))
                let small = MenuBarIcon.image(arcs: arcs, size: 18)
                small.lockFocus(); tint.set(); NSRect(x: 0, y: 0, width: 18, height: 18).fill(using: .sourceIn); small.unlockFocus()
                small.draw(in: NSRect(x: bg.minX + 55 + CGFloat(k) * 110, y: 12, width: 18, height: 18))
            }
        }
        return true
    }
    if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/menubar.png"))
    }
}

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
    app.setActivationPolicy(.accessory)
    snapshotHub(to: CommandLine.arguments[i + 1])
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
