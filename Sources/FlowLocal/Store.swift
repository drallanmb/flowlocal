import Foundation
import AppKit

extension Notification.Name {
    static let historyChanged = Notification.Name("flowlocal.historyChanged")
    static let restartWhisper = Notification.Name("flowlocal.restartWhisper")
    static let reloadLLM = Notification.Name("flowlocal.reloadLLM")
}

// MARK: - History

struct HistoryEntry: Identifiable, Equatable {
    let id: String
    let at: Date
    let seconds: Double
    let raw: String
    let text: String
    let app: String
    /// "dictation" or "command" (for commands, `raw` holds the spoken instruction).
    let kind: String

    var isCommand: Bool { kind == "command" }
    var words: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
}

/// Append-only JSON-lines log of dictations (the Hub's "Home" feed).
enum History {
    private static let iso = ISO8601DateFormatter()

    static func append(raw: String, text: String, seconds: Double, app: String, kind: String = "dictation") {
        let at = iso.string(from: Date())
        let entry: [String: Any] = [
            "id": UUID().uuidString,
            "at": at,
            "seconds": (seconds * 10).rounded() / 10,
            "raw": raw,
            "text": text,
            "app": app,
            "kind": kind,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry), var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let h = try? FileHandle(forWritingTo: Paths.history) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: Paths.history, atomically: true, encoding: .utf8)
        }
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    static func load() -> [HistoryEntry] {
        guard let s = try? String(contentsOf: Paths.history, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap { line in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let atStr = obj["at"] as? String, let at = iso.date(from: atStr),
                  let text = obj["text"] as? String else { return nil }
            // Entries written before v0.2 have no id/app.
            return HistoryEntry(id: obj["id"] as? String ?? "\(atStr)|\(text)",
                                at: at, seconds: obj["seconds"] as? Double ?? 0,
                                raw: obj["raw"] as? String ?? text, text: text,
                                app: obj["app"] as? String ?? "",
                                kind: obj["kind"] as? String ?? "dictation")
        }
        .sorted { $0.at > $1.at }
    }

    /// Rewrites the file without the given ids (oldest first on disk).
    static func remove(ids: Set<String>) {
        let keep = load().filter { !ids.contains($0.id) }.reversed()
        let lines = keep.map { e -> String in
            let o: [String: Any] = ["id": e.id, "at": iso.string(from: e.at), "seconds": e.seconds,
                                    "raw": e.raw, "text": e.text, "app": e.app, "kind": e.kind]
            return String(data: (try? JSONSerialization.data(withJSONObject: o)) ?? Data(), encoding: .utf8) ?? ""
        }
        try? (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(to: Paths.history, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private var token: NSObjectProtocol?

    init() {
        reload()
        token = NotificationCenter.default.addObserver(forName: .historyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }

    func reload() { entries = History.load() }
    func delete(_ id: String) { History.remove(ids: [id]) }
    func clear() { History.remove(ids: Set(entries.map(\.id))) }

    var totalWords: Int { entries.reduce(0) { $0 + $1.words } }
    var totalSeconds: Double { entries.reduce(0) { $0 + $1.seconds } }
    /// Words per minute of speaking time.
    var wpm: Int { totalSeconds > 1 ? Int(Double(totalWords) / (totalSeconds / 60)) : 0 }
}

// MARK: - Dictionary

struct DictEntry: Identifiable, Equatable {
    var id = UUID()
    var from: String
    var to: String
}

/// dictionary.json: `{"as spoken": "as written"}`. An entry whose two sides match is a plain "word to remember".
final class DictionaryStore: ObservableObject {
    @Published var items: [DictEntry] = []

    init() { reload() }

    func reload() {
        items = TextCleaner.loadDictionary()
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { DictEntry(from: $0.key, to: $0.value) }
    }

    func add(from: String, to: String) {
        let f = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else { return }
        items.removeAll { $0.from.caseInsensitiveCompare(f) == .orderedSame }
        items.append(DictEntry(from: f, to: t.isEmpty ? f : t))
        items.sort { $0.from.localizedCaseInsensitiveCompare($1.from) == .orderedAscending }
        save()
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id }; save() }

    func save() {
        var dict: [String: String] = [:]
        for i in items where !i.from.trimmingCharacters(in: .whitespaces).isEmpty {
            dict[i.from] = i.to.isEmpty ? i.from : i.to
        }
        if let data = try? JSONEncoder().encode(dict) { try? data.write(to: Paths.dictionary) }
    }
}

// MARK: - Snippets

struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

/// snippets.json: say the trigger phrase, get the longer text.
final class SnippetStore: ObservableObject {
    @Published var items: [Snippet] = []

    init() { items = Self.load() }

    static func load() -> [Snippet] {
        guard let d = try? Data(contentsOf: Paths.snippets) else { return [] }
        return (try? JSONDecoder().decode([Snippet].self, from: d)) ?? []
    }

    func add(trigger: String, expansion: String) {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !expansion.isEmpty else { return }
        items.removeAll { $0.trigger.caseInsensitiveCompare(t) == .orderedSame }
        items.append(Snippet(trigger: t, expansion: expansion))
        save()
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id }; save() }

    func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: Paths.snippets) }
    }

    /// Replaces spoken triggers in `text`. Returns the new text and whether any snippet fired.
    static func apply(to text: String) -> (String, Bool) {
        var out = text, hit = false
        for s in load().sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: s.trigger) + "\\b[,.!?]?"
            guard let re = try? NSRegularExpression(pattern: pattern),
                  re.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)) != nil else { continue }
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: s.expansion))
            hit = true
        }
        return (out, hit)
    }
}

// MARK: - Style (tone per kind of app, like Wispr's Style page)

enum AppCategory: String, CaseIterable, Identifiable {
    case email, work, personal, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .email: return "E-mail"
        case .work: return "Mensagens de trabalho"
        case .personal: return "Mensagens pessoais"
        case .other: return "Outros"
        }
    }

    var examples: String {
        switch self {
        case .email: return "Mail, Outlook"
        case .work: return "Slack, Teams, Zoom"
        case .personal: return "Mensagens, WhatsApp, Telegram, Discord"
        case .other: return "Todos os demais apps"
        }
    }

    static func of(bundleID: String?) -> AppCategory {
        switch bundleID ?? "" {
        case "com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac", "com.google.Gmail": return .email
        case "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams", "us.zoom.xos", "com.linear": return .work
        case "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.hnc.Discord", "org.whispersystems.signal-desktop": return .personal
        default: return .other
        }
    }

    var tone: Tone {
        get { Tone(rawValue: UserDefaults.standard.string(forKey: "tone.\(rawValue)") ?? "") ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "tone.\(rawValue)") }
    }
}

enum Tone: String, CaseIterable, Identifiable {
    case standard, formal, casual, concise
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Padrão"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .concise: return "Conciso"
        }
    }

    /// Extra instruction appended to the polish prompt.
    var instruction: String? {
        switch self {
        case .standard: return nil
        case .formal: return "Use tom formal e profissional, com maiúsculas e pontuação completas."
        case .casual: return "Use tom casual e natural, frases curtas; em mensagens de uma frase, dispense o ponto final."
        case .concise: return "Seja conciso: elimine redundâncias e rodeios, sem perder nenhuma informação."
        }
    }
}
