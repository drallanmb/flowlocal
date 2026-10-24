import Foundation

/// Rule-based post-processing: filler removal, spoken punctuation, personal dictionary.
/// (Wispr does this server-side with an LLM; this is the local, deterministic equivalent.)
enum TextCleaner {
    /// Personal dictionary: `{"from": "to"}` pairs in dictionary.json (case-insensitive, whole word).
    static func loadDictionary() -> [String: String] {
        guard let data = try? Data(contentsOf: Paths.dictionary),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    /// Terms to bias whisper toward (right-hand sides of the dictionary).
    static func dictionaryTerms() -> [String] { Set(loadDictionary().values).sorted() }

    static func promptHint() -> String {
        let terms = dictionaryTerms()
        return terms.isEmpty ? "" : terms.joined(separator: ", ") + "."
    }

    static func clean(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return t }

        if Settings.cleanFillers {
            // Hesitations. Kept narrow on purpose: "um" and "er" are real words in pt/de, so they stay.
            // Whisper often renders a hesitation as "uu"/"uh"/"hum", so match those spellings.
            t = replace(t, #"(?i)\b(?:hum+|hmm+|ahn+|eh+m?|uh+m?|uu+h?m?)\b[,.]?\s*"#, "")
        }

        // Spoken punctuation / layout commands (accent-insensitive: whisper drops accents sometimes).
        let spoken: [(String, String)] = [
            (#"(?i)\s*\bnova linha\b[,.]?\s*"#, "\n"),
            (#"(?i)\s*\bnovo par[aá]grafo\b[,.]?\s*"#, "\n\n"),
            (#"(?i)\s*\bponto de interroga[cç][aã]o\b[,.]?"#, "?"),
            (#"(?i)\s*\bponto de exclama[cç][aã]o\b[,.]?"#, "!"),
            (#"(?i)\s*\bponto final\b[,.]?"#, "."),
            (#"(?i)\s*\bdois pontos\b[,.]?"#, ":"),
            (#"(?i)\s*\bponto e v[ií]rgula\b[,.]?"#, ";"),
            (#"(?i)\s*\bv[ií]rgula\b[,.]?"#, ","),
        ]
        for (pattern, repl) in spoken { t = replace(t, pattern, repl) }
        // Collapse punctuation doubled by a spoken command next to whisper's own.
        t = replace(t, #",\s*,"#, ",")
        t = replace(t, #"[,;:]\s*([.!?])"#, "$1")
        t = replace(t, #"([.!?])\s*\1+"#, "$1")

        // Personal dictionary.
        for (from, to) in loadDictionary() {
            let escaped = NSRegularExpression.escapedPattern(for: from)
            t = replace(t, "(?i)\\b\(escaped)\\b", NSRegularExpression.escapedTemplate(for: to))
        }

        // Whitespace + sentence-start capitalisation.
        t = replace(t, #"[ \t]{2,}"#, " ")
        t = replace(t, #"\s+([,.;:!?])"#, "$1")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = t.first, first.isLowercase { t = first.uppercased() + t.dropFirst() }
        return t
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}
