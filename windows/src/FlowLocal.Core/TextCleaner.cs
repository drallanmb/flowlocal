using System.Text.Json;
using System.Text.RegularExpressions;

namespace FlowLocal.Core;

/// <summary>Rule-based post-processing: filler removal, spoken punctuation, personal dictionary.</summary>
public static class TextCleaner
{
    /// <summary>dictionary.json: {"as spoken": "as written"}.</summary>
    public static Dictionary<string, string> LoadDictionary()
    {
        try
        {
            if (File.Exists(AppPaths.Dictionary))
                return JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(AppPaths.Dictionary)) ?? new();
        }
        catch (Exception e) { Log.Write($"dictionary load failed: {e.Message}"); }
        return new();
    }

    /// <summary>Terms to bias whisper toward (right-hand sides of the dictionary).</summary>
    public static IReadOnlyList<string> DictionaryTerms() =>
        LoadDictionary().Values.Distinct(StringComparer.Ordinal).OrderBy(v => v, StringComparer.Ordinal).ToList();

    public static string PromptHint()
    {
        var terms = DictionaryTerms();
        return terms.Count == 0 ? "" : string.Join(", ", terms) + ".";
    }

    private static readonly (string Pattern, string Replacement)[] Spoken =
    {
        (@"(?i)\s*\bnova linha\b[,.]?\s*", "\n"),
        (@"(?i)\s*\bnovo par[aá]grafo\b[,.]?\s*", "\n\n"),
        (@"(?i)\s*\bponto de interroga[cç][aã]o\b[,.]?", "?"),
        (@"(?i)\s*\bponto de exclama[cç][aã]o\b[,.]?", "!"),
        (@"(?i)\s*\bponto final\b[,.]?", "."),
        (@"(?i)\s*\bdois pontos\b[,.]?", ":"),
        (@"(?i)\s*\bponto e v[ií]rgula\b[,.]?", ";"),
        (@"(?i)\s*\bv[ií]rgula\b[,.]?", ","),
    };

    public static string Clean(string raw, bool cleanFillers, IReadOnlyDictionary<string, string>? dictionary = null)
    {
        var t = raw.Trim();
        if (t.Length == 0) return t;

        if (cleanFillers)
        {
            // Hesitations. Narrow on purpose: "um" and "er" are real words, so they stay.
            // Whisper often renders a hesitation as "uu"/"uh"/"hum", so match those spellings.
            t = Regex.Replace(t, @"(?i)\b(?:hum+|hmm+|ahn+|eh+m?|uh+m?|uu+h?m?)\b[,.]?\s*", "");
        }

        // Spoken punctuation / layout commands (accent-insensitive: whisper drops accents sometimes).
        foreach (var (pattern, replacement) in Spoken) t = Regex.Replace(t, pattern, replacement);

        // Collapse punctuation doubled by a spoken command next to whisper's own.
        t = Regex.Replace(t, @",\s*,", ",");
        t = Regex.Replace(t, @"[,;:]\s*([.!?])", "$1");
        t = Regex.Replace(t, @"([.!?])\s*\1+", "$1");

        foreach (var (from, to) in dictionary ?? LoadDictionary())
            t = Regex.Replace(t, @"(?i)\b" + Regex.Escape(from) + @"\b", _ => to);

        t = Regex.Replace(t, @"[ \t]{2,}", " ");
        t = Regex.Replace(t, @"\s+([,.;:!?])", "$1");
        t = t.Trim();
        if (t.Length > 0 && char.IsLower(t[0])) t = char.ToUpperInvariant(t[0]) + t[1..];
        return t;
    }
}
