namespace FlowLocal.Core;

/// <summary>Append-only diagnostic log: key codes, setup state, pipeline stages and errors (never dictated text).</summary>
public static class Log
{
    private static readonly object Gate = new();

    public static void Write(string message)
    {
        try
        {
            lock (Gate)
            {
                var file = new FileInfo(AppPaths.LogFile);
                if (file.Exists && file.Length > 512_000) file.Delete();   // crude rotation
                File.AppendAllText(AppPaths.LogFile, $"{DateTime.UtcNow:yyyy-MM-ddTHH:mm:ssZ} {message}{Environment.NewLine}");
            }
        }
        catch { /* logging must never break dictation */ }
    }
}
