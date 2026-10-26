using System.Text.Json;
using System.Text.Json.Serialization;

namespace FlowLocal.Core;

/// <summary>A key that can be held to dictate. Windows has no readable Fn key, so these are real virtual keys.</summary>
public sealed record HotkeyKey(string Id, string Title, int Vk)
{
    public static readonly IReadOnlyList<HotkeyKey> All = new[]
    {
        new HotkeyKey("RightCtrl", "Ctrl direito", 0xA3),
        new HotkeyKey("RightAlt", "Alt direito (AltGr em teclados ABNT2)", 0xA5),
        new HotkeyKey("RightShift", "Shift direito", 0xA1),
        new HotkeyKey("ScrollLock", "Scroll Lock", 0x91),
        new HotkeyKey("Pause", "Pause/Break", 0x13),
        new HotkeyKey("F9", "F9", 0x78),
        new HotkeyKey("F10", "F10", 0x79),
        new HotkeyKey("F11", "F11", 0x7A),
        new HotkeyKey("F12", "F12", 0x7B),
    };

    public static HotkeyKey? Find(string? id) => All.FirstOrDefault(k => k.Id == id);
}

/// <summary>User settings, stored as JSON in %APPDATA%\FlowLocal\settings.json.</summary>
public sealed class Settings
{
    public string Hotkey { get; set; } = "RightCtrl";
    /// <summary>Hold-to-talk key for command mode (edit the selection by voice); null = off.</summary>
    public string? CommandHotkey { get; set; }
    public string Language { get; set; } = "pt";
    public string WhisperModel { get; set; } = "ggml-large-v3-turbo-q5_0.bin";
    /// <summary>Full path to whisper-server.exe; empty = search the usual places.</summary>
    public string WhisperServerPath { get; set; } = "";
    public bool CleanFillers { get; set; } = true;
    public bool LlmEnabled { get; set; } = true;
    public string LlmModel { get; set; } = "qwen2.5:3b-instruct";
    /// <summary>A quick tap latches recording on; tap again to finish.</summary>
    public bool HandsFree { get; set; } = true;
    public bool FieldContext { get; set; } = true;
    public bool ScreenOcr { get; set; }
    public bool OpenHubOnStart { get; set; } = true;
    /// <summary>Tone per app category ("email", "work", "personal", "other") -> tone id.</summary>
    public Dictionary<string, string> Tones { get; set; } = new();

    [JsonIgnore] public HotkeyKey DictationKey => HotkeyKey.Find(Hotkey) ?? HotkeyKey.All[0];
    [JsonIgnore] public HotkeyKey? CommandKey => HotkeyKey.Find(CommandHotkey) is { } k && k.Id != Hotkey ? k : null;

    public const int WhisperPort = 8178;

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };
    private static Settings? _current;

    public static event Action? Changed;

    public static Settings Current => _current ??= Load();

    public static Settings Load()
    {
        try
        {
            if (File.Exists(AppPaths.SettingsFile))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(AppPaths.SettingsFile)) ?? new Settings();
        }
        catch (Exception e) { Log.Write($"settings load failed: {e.Message}"); }
        return new Settings();
    }

    public void Save()
    {
        try { File.WriteAllText(AppPaths.SettingsFile, JsonSerializer.Serialize(this, Json)); }
        catch (Exception e) { Log.Write($"settings save failed: {e.Message}"); }
        Changed?.Invoke();
    }
}
