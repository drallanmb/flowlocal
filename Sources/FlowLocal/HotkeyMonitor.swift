import AppKit

/// Hold-to-talk for two keys: the dictation key and the (optional) command-mode key.
/// Uses a global NSEvent monitor (needs Input Monitoring / Accessibility permission).
final class HotkeyMonitor {
    enum Mode { case dictation, command }

    var onPress: ((Mode) -> Void)?
    var onRelease: ((Mode) -> Void)?
    /// Escape pressed anywhere (the app only acts on it while recording).
    var onCancel: (() -> Void)?

    private var monitor: Any?
    private var keyMonitor: Any?
    /// The mode whose key is currently held; the other key is ignored until it is released.
    private var active: Mode?

    func start() {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.onCancel?() }
        }
        Log.write("hotkey monitor \(monitor == nil ? "FAILED to install" : "installed")")
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if let k = keyMonitor { NSEvent.removeMonitor(k) }
        keyMonitor = nil
        active = nil
    }

    private func handle(_ event: NSEvent) {
        let code = Int(event.keyCode)
        Log.write("flagsChanged keyCode=\(code) flags=\(event.modifierFlags.rawValue)")
        let dictation = Settings.hotkey
        let mode: Mode
        let key: Hotkey
        if code == dictation.rawValue {
            mode = .dictation; key = dictation
        } else if let cmd = Settings.commandHotkey, cmd != dictation, code == cmd.rawValue {
            mode = .command; key = cmd
        } else {
            return
        }

        let flag: NSEvent.ModifierFlags
        switch key {
        case .rightOption: flag = .option
        case .rightCommand: flag = .command
        case .rightControl: flag = .control
        case .fn: flag = .function
        }
        let down = event.modifierFlags.contains(flag)
        if down && active == nil {
            active = mode
            onPress?(mode)
        } else if !down && active == mode {
            active = nil
            onRelease?(mode)
        }
    }
}
