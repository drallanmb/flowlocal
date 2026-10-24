import Foundation

/// Hold-to-talk trigger keys (modifier keys, matched by virtual key code).
enum Hotkey: Int, CaseIterable {
    case rightOption = 61
    case rightCommand = 54
    case rightControl = 62
    case fn = 63

    var title: String {
        switch self {
        case .rightOption: return "Option direito"
        case .rightCommand: return "Command direito"
        case .rightControl: return "Control direito"
        case .fn: return "Fn / Globe"
        }
    }
}

enum Paths {
    static let support: URL = {
        // FLOWLOCAL_DATA_DIR lets tests and snapshots run against throwaway data.
        let url = ProcessInfo.processInfo.environment["FLOWLOCAL_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FlowLocal", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static let models = support.appendingPathComponent("models", isDirectory: true)
    static let dictionary = support.appendingPathComponent("dictionary.json")
    static let history = support.appendingPathComponent("history.jsonl")
    static let snippets = support.appendingPathComponent("snippets.json")
    static let scratchpad = support.appendingPathComponent("scratchpad.txt")
}

struct Settings {
    private static let d = UserDefaults.standard

    static var hotkey: Hotkey {
        get { Hotkey(rawValue: d.integer(forKey: "hotkey")) ?? .rightOption }
        set { d.set(newValue.rawValue, forKey: "hotkey") }
    }

    /// Hold-to-talk key for command mode (edit the selected text by voice). nil = off.
    static var commandHotkey: Hotkey? {
        get { Hotkey(rawValue: d.object(forKey: "commandHotkey") as? Int ?? Hotkey.rightControl.rawValue) }
        set { d.set(newValue?.rawValue ?? 0, forKey: "commandHotkey") }
    }

    /// "auto", "pt", "en", ...
    static var language: String {
        get { d.string(forKey: "language") ?? "pt" }
        set { d.set(newValue, forKey: "language") }
    }

    static var modelFile: String {
        get { d.string(forKey: "model") ?? "ggml-large-v3-turbo-q5_0.bin" }
        set { d.set(newValue, forKey: "model") }
    }

    static var cleanFillers: Bool {
        get { d.object(forKey: "cleanFillers") as? Bool ?? true }
        set { d.set(newValue, forKey: "cleanFillers") }
    }

    /// Quick tap on the hotkey latches recording on (hands-free); tap again to finish.
    static var handsFree: Bool {
        get { d.object(forKey: "handsFree") as? Bool ?? true }
        set { d.set(newValue, forKey: "handsFree") }
    }

    /// Read the focused text field (before/after the caret) and window title through Accessibility.
    static var fieldContext: Bool {
        get { d.object(forKey: "fieldContext") as? Bool ?? true }
        set { d.set(newValue, forKey: "fieldContext") }
    }

    /// OCR the focused window while you speak (needs Screen Recording permission).
    static var screenOCR: Bool {
        get { d.object(forKey: "screenOCR") as? Bool ?? false }
        set { d.set(newValue, forKey: "screenOCR") }
    }

    static var llmEnabled: Bool {
        get { d.object(forKey: "llmEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "llmEnabled") }
    }

    static var llmModel: String {
        get { d.string(forKey: "llmModel") ?? "qwen2.5:3b-instruct" }
        set { d.set(newValue, forKey: "llmModel") }
    }

    static var whisperServerPath: String {
        for p in ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "/opt/homebrew/bin/whisper-server"
    }

    static let port = 8178
}
