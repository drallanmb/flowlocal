using System.Text.RegularExpressions;

namespace FlowLocal.Core;

/// <summary>What is on screen around the caret when you start talking. Used locally (never sent anywhere).</summary>
public sealed class ScreenContext
{
    public string AppName { get; set; } = "";
    public string WindowTitle { get; set; } = "";
    /// <summary>Text of the focused field before / after the caret (UI Automation).</summary>
    public string Before { get; set; } = "";
    public string After { get; set; } = "";
    /// <summary>Text recognised on the focused window (optional OCR).</summary>
    public string Ocr { get; set; } = "";

    public bool IsEmpty => Before.Length == 0 && After.Length == 0 && Ocr.Length == 0 && WindowTitle.Length == 0;

    private static readonly Regex TermRe = new(@"\b(?:[A-ZÀ-Ý][\p{L}\d]{2,}|[a-z]+[A-Z][\p{L}\d]*)\b", RegexOptions.Compiled);

    /// <summary>Likely names and jargon seen on screen (capitalised or camelCase words), most frequent first.</summary>
    public IReadOnlyList<string> Terms()
    {
        var text = string.Join("\n", WindowTitle, Before, After, Ocr);
        var count = new Dictionary<string, int>();
        foreach (Match m in TermRe.Matches(text)) count[m.Value] = count.GetValueOrDefault(m.Value) + 1;
        return count.OrderByDescending(kv => kv.Value).ThenBy(kv => kv.Key, StringComparer.Ordinal).Take(24).Select(kv => kv.Key).ToList();
    }

    /// <summary>Appended to whisper's initial prompt (whisper only reads the last ~220 tokens, so keep it short).</summary>
    public string WhisperHint()
    {
        var joined = string.Join(", ", Terms());
        if (joined.Length == 0) return "";
        return " " + (joined.Length > 350 ? joined[..350] : joined) + ".";
    }

    private static string Tail(string s, int n) =>
        (s.Length > n ? s[^n..] : s).Replace("</screen_context>", "");

    /// <summary>Untrusted screen text for the LLM prompt, unable to close its own tag.</summary>
    public string PromptBlock()
    {
        var lines = new List<string>();
        if (AppName.Length > 0) lines.Add($"App: {AppName}");
        if (WindowTitle.Length > 0) lines.Add($"Janela: {Tail(WindowTitle, 120)}");
        if (Before.Length > 0) lines.Add($"Texto antes do cursor: «{Tail(Before, 500)}»");
        if (After.Length > 0) lines.Add($"Texto depois do cursor: «{Tail(After, 200)}»");
        if (Ocr.Length > 0) lines.Add($"Texto visível na janela: «{Tail(Ocr, 1200)}»");
        return string.Join("\n", lines);
    }
}

/// <summary>Fits dictated text to the field it lands in: the space after the caret's neighbour and mid-sentence casing.</summary>
public static class ContextFit
{
    public static string Fit(string text, ScreenContext? ctx, IEnumerable<string> knownTerms)
    {
        if (ctx is null || ctx.Before.Length == 0 || text.Length == 0) return text;
        if (text.StartsWith(' ') || text.StartsWith('\n')) return text;
        var before = ctx.Before;
        var t = text;
        var first = t[0];

        // Last visible character, and whether the caret sits at the start of a line.
        char? lastVisible = null;
        for (var i = before.Length - 1; i >= 0; i--)
            if (!char.IsWhiteSpace(before[i])) { lastVisible = before[i]; break; }
        var atLineStart = true;
        for (var i = before.Length - 1; i >= 0; i--)
        {
            if (before[i] is '\n' or '\r') { atLineStart = true; break; }
            if (!char.IsWhiteSpace(before[i])) { atLineStart = false; break; }
        }

        // Continuing a sentence: "…vou ao" + "Mercado" -> "mercado" (unless it looks like a name or acronym).
        if (lastVisible is { } last && !atLineStart && ".!?…:;".IndexOf(last) < 0 && char.IsUpper(first))
        {
            var word = new string(t.TakeWhile(char.IsLetterOrDigit).ToArray());
            var rest = word.Length > 0 ? word[1..] : "";
            var looksPlain = word.Length > 1 && rest == rest.ToLowerInvariant();
            var isKnown = knownTerms.Any(k => string.Equals(k, word, StringComparison.OrdinalIgnoreCase));
            if (looksPlain && !isKnown) t = char.ToLowerInvariant(first) + t[1..];
        }

        // Keep words from gluing together when the caret sits right after a non-space character.
        var lastChar = before[^1];
        if (!char.IsWhiteSpace(lastChar) && "([{\"'“‘«/-".IndexOf(lastChar) < 0 && ",.;:!?)]}".IndexOf(t[0]) < 0)
            t = " " + t;
        return t;
    }
}
