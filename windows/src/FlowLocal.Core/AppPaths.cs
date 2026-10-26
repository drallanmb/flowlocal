namespace FlowLocal.Core;

/// <summary>Where FlowLocal keeps its data (%APPDATA%\FlowLocal). FLOWLOCAL_DATA_DIR overrides it for tests.</summary>
public static class AppPaths
{
    public static string Support { get; } = Init();

    private static string Init()
    {
        var over = Environment.GetEnvironmentVariable("FLOWLOCAL_DATA_DIR");
        var path = !string.IsNullOrEmpty(over)
            ? over
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "FlowLocal");
        Directory.CreateDirectory(path);
        return path;
    }

    public static string Models => Directory.CreateDirectory(Path.Combine(Support, "models")).FullName;
    public static string Dictionary => Path.Combine(Support, "dictionary.json");
    public static string Snippets => Path.Combine(Support, "snippets.json");
    public static string History => Path.Combine(Support, "history.jsonl");
    public static string Scratchpad => Path.Combine(Support, "scratchpad.txt");
    public static string SettingsFile => Path.Combine(Support, "settings.json");
    public static string LogFile => Path.Combine(Support, "flowlocal.log");

    /// <summary>Where setup.ps1 unpacks whisper.cpp (whisper-server.exe).</summary>
    public static string WhisperDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FlowLocal", "whisper");
}
