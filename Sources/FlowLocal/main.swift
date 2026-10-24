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
    /// Hands-free: a quick tap latches recording on; the next tap finishes it.
    private var latched = false
    private var pressedAt = Date()
    private var swallowRelease = false
    private var latchToken = 0
    /// Screen context captured when the hotkey went down (field text via Accessibility; OCR runs while you speak).
    private var contextAtStart: ScreenContext?
    private var ocrTask: Task<String, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setIcon(active: false)
        rebuildMenu()
        requestPermissions()
        Log.write("launch: accessibility=\(AXIsProcessTrusted()) inputMonitoring=\(CGPreflightListenEventAccess()) mic=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) dictationKey=\(Settings.hotkey) commandKey=\(String(describing: Settings.commandHotkey)) bundle=\(Bundle.main.bundlePath)")

        recorder.onLevel = { [weak self] in self?.overlay.setLevel($0) }
        hotkey.onPress = { [weak self] in self?.hotkeyPressed($0) }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased($0) }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        hotkey.start()
        if Settings.llmEnabled || Settings.commandHotkey != nil { polisher.prepare() }
        startWhisper()
        if Settings.screenOCR { ScreenContext.warmUpOCR() }

        // The Hub edits UserDefaults directly; keep the menu and background services in sync.
        let nc = NotificationCenter.default
        nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuildMenu() }
        nc.addObserver(forName: .restartWhisper, object: nil, queue: .main) { [weak self] _ in self?.startWhisper() }
        nc.addObserver(forName: .reloadLLM, object: nil, queue: .main) { [weak self] _ in
            if Settings.llmEnabled || Settings.commandHotkey != nil { self?.polisher.prepare() }
        }

        // A key monitor created before Input Monitoring / Accessibility were granted receives nothing; recreate it.
        nc.addObserver(forName: .permissionsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.hotkey.start()
            if PermissionsModel.shared.currentStep == nil { self?.setStatus("Pronto — segure \(Settings.hotkey.title)") }
            else { self?.requestPermissions() }
        }

        HubWindow.shared.show()

        // Where did macOS put the menu bar item? (An item with no room, or switched off in Settings → Menu Bar, has no usable frame.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let b = self.statusItem.button
            if let b, let rep = b.bitmapImageRepForCachingDisplay(in: b.bounds) {
                b.cacheDisplay(in: b.bounds, to: rep)
                var inked = 0
                for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { inked += 1 } }
                Log.write("status button render: \(rep.pixelsWide)x\(rep.pixelsHigh) px, \(inked) inked")
                try? rep.representation(using: .png, properties: [:])?.write(to: Paths.support.appendingPathComponent("statusbutton.png"))
            }
            Log.write("status item: visible=\(self.statusItem.isVisible) image=\(String(describing: b?.image?.size)) windowFrame=\(String(describing: b?.window?.frame)) screens=\(NSScreen.screens.map(\.frame))")
        }
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
                case .success: Log.write("whisper-server ready"); self?.setStatus("Pronto — segure \(Settings.hotkey.title)")
                case .failure(let e): Log.write("whisper-server failed: \(e.localizedDescription)"); self?.setStatus("Erro: \(e.localizedDescription)")
                }
            }
        }
    }

    // MARK: Hotkey state machine (push-to-talk + hands-free)

    private func hotkeyPressed(_ mode: HotkeyMonitor.Mode) {
        if recorder.isRecording && latched {
            // Second tap while hands-free: finish now and ignore the release that follows.
            latched = false
            swallowRelease = true
            endDictation()
            return
        }
        pressedAt = Date()
        beginDictation(mode)
    }

    private func hotkeyReleased(_ mode: HotkeyMonitor.Mode) {
        if swallowRelease { swallowRelease = false; return }
        guard recorder.isRecording else { return }
        if Settings.handsFree, Date().timeIntervalSince(pressedAt) < 0.3 {
            latched = true
            overlay.show("Mãos livres: toque para finalizar · Esc cancela", color: .systemRed)
            // Safety net: never record forever if the user walks away.
            latchToken += 1
            let token = latchToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
                guard let self, self.latched, self.latchToken == token else { return }
                self.latched = false
                self.endDictation()
            }
            return
        }
        endDictation()
    }

    private func cancelRecording() {
        guard recorder.isRecording else { return }
        _ = recorder.stop()
        latched = false
        ocrTask?.cancel()
        setIcon(active: false)
        Log.write("recording cancelled with Esc")
        overlay.show("Cancelado", color: .systemGray)
        overlay.hide(after: 1)
    }

    // MARK: Dictation flow

    private func beginDictation(_ mode: HotkeyMonitor.Mode) {
        Log.write("begin \(mode) whisperReady=\(whisper.isReady)")
        guard whisper.isReady else { overlay.show("Carregando modelo…", color: .systemOrange); overlay.hide(after: 1.5); return }
        do {
            // Our own windows (Hub) count too: dictating into the Scratchpad is a supported use.
            targetApp = NSWorkspace.shared.frontmostApplication
            self.mode = mode
            // Context is read now, while the target app still has focus. OCR runs in the background during recording.
            contextAtStart = nil
            ocrTask?.cancel(); ocrTask = nil
            if mode == .dictation {
                if Settings.fieldContext { contextAtStart = ScreenContext.fromAccessibility(app: targetApp) }
                if Settings.screenOCR, let app = targetApp, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    ocrTask = Task { await ScreenContext.ocr(app: app) }
                }
            }
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
            Log.write("recorder start failed: \(error.localizedDescription)")
            overlay.show("Sem microfone", color: .systemOrange); overlay.hide(after: 2)
        }
    }

    private func endDictation() {
        guard recorder.isRecording else { return }
        let samples = recorder.stop()
        setIcon(active: false)
        Log.write("end: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16_000)) s), peak=\(samples.map { abs($0) }.max() ?? 0)")

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

        let startContext = contextAtStart
        let pendingOCR = ocrTask
        Task {
            do {
                var context = startContext ?? ScreenContext(appName: appName)
                if let pendingOCR { context.ocr = await ScreenContext.result(of: pendingOCR, timeout: 1.5) }
                if !context.isEmpty { Log.write("context: field=\(context.before.count)+\(context.after.count) chars, ocr=\(context.ocr.count) chars, terms=\(context.terms.count)") }
                let raw = try await whisper.transcribe(wav: wav, language: language, prompt: hint + context.whisperHint)
                let (expanded, usedSnippet) = SnippetStore.apply(to: TextCleaner.clean(raw))
                var polished = expanded
                // Snippet expansions are verbatim text the user wrote; keep the LLM away from them.
                if Settings.llmEnabled, !expanded.isEmpty, !usedSnippet {
                    overlay.show("Polindo…", color: .systemPurple)
                    polished = await polisher.polish(expanded, dictionaryTerms: TextCleaner.dictionaryTerms(), tone: tone, context: context)
                }
                let text = Settings.fieldContext
                    ? ContextFit.fit(polished, to: context, knownTerms: TextCleaner.dictionaryTerms() + context.terms)
                    : polished
                await MainActor.run {
                    if text.isEmpty {
                        overlay.show("Nada detectado", color: .systemGray); overlay.hide(after: 1.2)
                    } else {
                        Log.write("dictation ok: \(text.count) chars")
                        deliver(text)
                        History.append(raw: raw, text: text, seconds: seconds, app: appName)
                    }
                }
            } catch {
                Log.write("dictation failed: \(error.localizedDescription)")
                await MainActor.run {
                    overlay.show("Falha: \(error.localizedDescription)", color: .systemRed)
                    overlay.hide(after: 3)
                }
            }
        }
    }

    /// Pastes into the focused app; without Accessibility the synthetic Cmd+V is silently dropped, so keep the text on the clipboard instead.
    private func deliver(_ text: String) {
        if AXIsProcessTrusted() {
            TextInserter.insert(text)
            overlay.hide()
        } else {
            Log.write("paste skipped: accessibility not granted, text left on clipboard")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            overlay.show("Sem Acessibilidade — texto copiado (⌘V)", color: .systemOrange)
            overlay.hide(after: 4)
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
                        deliver(result)
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

    /// Permissions are requested one at a time by the guide in the Hub, never all at once at launch.
    private func requestPermissions() {
        if let step = PermissionsModel.shared.currentStep {
            setStatus("Falta liberar \(step.title): abra o Hub e siga o passo a passo")
        }
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
