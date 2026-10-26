using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace FlowLocal.Core;

public sealed record HistoryEntry(string Id, DateTime At, double Seconds, string Raw, string Text, string App, string Kind)
{
    public bool IsCommand => Kind == "command";
    public int Words => Text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
}

/// <summary>history.jsonl: one JSON object per dictation (same schema as the macOS app).</summary>
public static class History
{
    private static readonly object Gate = new();
    public static event Action? Changed;

    public static void Append(string raw, string text, double seconds, string app, string kind = "dictation")
    {
        var obj = new JsonObject
        {
            ["id"] = Guid.NewGuid().ToString(),
            ["at"] = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            ["seconds"] = Math.Round(seconds, 1),
            ["raw"] = raw,
            ["text"] = text,
            ["app"] = app,
            ["kind"] = kind,
        };
        lock (Gate) File.AppendAllText(AppPaths.History, obj.ToJsonString() + Environment.NewLine);
        Changed?.Invoke();
    }

    public static List<HistoryEntry> Load()
    {
        var list = new List<HistoryEntry>();
        string[] lines;
        lock (Gate) lines = File.Exists(AppPaths.History) ? File.ReadAllLines(AppPaths.History) : Array.Empty<string>();
        foreach (var line in lines)
        {
            try
            {
                if (JsonNode.Parse(line) is not JsonObject o) continue;
                var atText = o["at"]?.GetValue<string>();
                var text = o["text"]?.GetValue<string>();
                if (atText is null || text is null) continue;
                var at = DateTime.Parse(atText, null, System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal);
                list.Add(new HistoryEntry(
                    o["id"]?.GetValue<string>() ?? $"{atText}|{text}", at,
                    o["seconds"]?.GetValue<double>() ?? 0, o["raw"]?.GetValue<string>() ?? text, text,
                    o["app"]?.GetValue<string>() ?? "", o["kind"]?.GetValue<string>() ?? "dictation"));
            }
            catch { /* skip a corrupt line */ }
        }
        return list.OrderByDescending(e => e.At).ToList();
    }

    public static void Remove(ISet<string> ids)
    {
        var keep = Load().Where(e => !ids.Contains(e.Id)).Reverse().Select(e => new JsonObject
        {
            ["id"] = e.Id, ["at"] = e.At.ToString("yyyy-MM-ddTHH:mm:ssZ"), ["seconds"] = e.Seconds,
            ["raw"] = e.Raw, ["text"] = e.Text, ["app"] = e.App, ["kind"] = e.Kind,
        }.ToJsonString());
        lock (Gate) File.WriteAllLines(AppPaths.History, keep);
        Changed?.Invoke();
    }
}

public sealed class DictEntry
{
    public string From { get; set; } = "";
    public string To { get; set; } = "";
}

public static class DictionaryStore
{
    public static List<DictEntry> Load() => TextCleaner.LoadDictionary()
        .OrderBy(kv => kv.Key, StringComparer.CurrentCultureIgnoreCase)
        .Select(kv => new DictEntry { From = kv.Key, To = kv.Value }).ToList();

    public static void Save(IEnumerable<DictEntry> items)
    {
        var dict = new Dictionary<string, string>();
        foreach (var i in items.Where(i => i.From.Trim().Length > 0)) dict[i.From.Trim()] = i.To.Length == 0 ? i.From.Trim() : i.To;
        File.WriteAllText(AppPaths.Dictionary, JsonSerializer.Serialize(dict));
    }
}

public sealed class Snippet
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Trigger { get; set; } = "";
    public string Expansion { get; set; } = "";
}

/// <summary>snippets.json: say the trigger phrase, get the longer text (inserted verbatim, no LLM).</summary>
public static class SnippetStore
{
    public static List<Snippet> Load()
    {
        try
        {
            if (File.Exists(AppPaths.Snippets))
                return JsonSerializer.Deserialize<List<Snippet>>(File.ReadAllText(AppPaths.Snippets)) ?? new();
        }
        catch (Exception e) { Log.Write($"snippets load failed: {e.Message}"); }
        return new();
    }

    public static void Save(IEnumerable<Snippet> items) =>
        File.WriteAllText(AppPaths.Snippets, JsonSerializer.Serialize(items.ToList()));

    /// <summary>Replaces spoken triggers in <paramref name="text"/>; reports whether any snippet fired.</summary>
    public static (string Text, bool Hit) Apply(string text, IEnumerable<Snippet>? snippets = null)
    {
        var hit = false;
        foreach (var s in (snippets ?? Load()).Where(s => s.Trigger.Length > 0).OrderByDescending(s => s.Trigger.Length))
        {
            var re = new Regex(@"(?i)\b" + Regex.Escape(s.Trigger) + @"\b[,.!?]?");
            if (!re.IsMatch(text)) continue;
            text = re.Replace(text, _ => s.Expansion);
            hit = true;
        }
        return (text, hit);
    }
}
