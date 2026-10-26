using System.Diagnostics;
using System.Net.Http.Json;
using System.Text.Json.Nodes;

namespace FlowLocal.Core;

/// <summary>Owns a local whisper.cpp `whisper-server.exe` so the model stays loaded between dictations.</summary>
public sealed class WhisperServer
{
    private readonly HttpClient _http = new() { BaseAddress = new Uri($"http://127.0.0.1:{Settings.WhisperPort}"), Timeout = TimeSpan.FromMinutes(2) };
    private Process? _process;

    public bool IsReady { get; private set; }

    /// <summary>Called with a process we start, so the app can tie its lifetime to ours (job object).</summary>
    public Action<Process>? OnProcessStarted { get; set; }

    public static string? FindServerExe(Settings s)
    {
        var candidates = new List<string>();
        if (s.WhisperServerPath.Length > 0) candidates.Add(s.WhisperServerPath);
        candidates.Add(Path.Combine(AppPaths.WhisperDir, "whisper-server.exe"));
        candidates.Add(Path.Combine(AppContext.BaseDirectory, "whisper", "whisper-server.exe"));
        if (Directory.Exists(AppPaths.WhisperDir))
            candidates.AddRange(Directory.EnumerateFiles(AppPaths.WhisperDir, "whisper-server.exe", SearchOption.AllDirectories));
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
            if (dir.Length > 0) candidates.Add(Path.Combine(dir, "whisper-server.exe"));
        return candidates.FirstOrDefault(File.Exists);
    }

    public static string ModelPath(Settings s) => Path.Combine(AppPaths.Models, s.WhisperModel);

    public static IReadOnlyList<string> InstalledModels() =>
        Directory.EnumerateFiles(AppPaths.Models, "*.bin").Select(Path.GetFileName).Where(n => n is not null).Select(n => n!).OrderBy(n => n).ToList();

    /// <summary>Starts the server (or adopts one already answering on the port) and waits until it responds.</summary>
    public async Task<string?> StartAsync()
    {
        Stop();
        var s = Settings.Current;
        if (await PingAsync()) { IsReady = true; Log.Write("whisper-server already running on the port, reusing it"); return null; }

        var exe = FindServerExe(s);
        if (exe is null) return "whisper-server.exe não encontrado. Rode windows\\scripts\\setup.ps1 ou informe o caminho em Configurações.";
        var model = ModelPath(s);
        if (!File.Exists(model)) return $"Modelo não encontrado: {model}";

        var threads = Math.Clamp(Environment.ProcessorCount / 2, 4, 8);
        var psi = new ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(exe)!,   // DLLs (ggml, CUDA) sit next to the exe
        };
        foreach (var a in new[] { "-m", model, "--host", "127.0.0.1", "--port", Settings.WhisperPort.ToString(), "-l", "auto", "-nt", "-sns", "-t", threads.ToString() })
            psi.ArgumentList.Add(a);
        try
        {
            _process = Process.Start(psi);
            if (_process is not null) OnProcessStarted?.Invoke(_process);
        }
        catch (Exception e) { return $"Falha ao iniciar o whisper-server: {e.Message}"; }

        for (var i = 0; i < 240; i++)
        {
            if (_process is null || _process.HasExited) return "O whisper-server fechou ao iniciar (veja o log).";
            if (await PingAsync()) { IsReady = true; Log.Write("whisper-server ready"); return null; }
            await Task.Delay(500);
        }
        return "O whisper-server demorou demais para carregar o modelo.";
    }

    public void Stop()
    {
        IsReady = false;
        try { if (_process is { HasExited: false }) _process.Kill(true); } catch { }
        _process = null;
    }

    private async Task<bool> PingAsync()
    {
        try
        {
            using var cts = new CancellationTokenSource(1500);
            using var r = await _http.GetAsync("", cts.Token);
            return true;
        }
        catch { return false; }
    }

    /// <summary>Sends a WAV to whisper-server and returns the raw transcript.</summary>
    public async Task<string> TranscribeAsync(byte[] wav, string language, string prompt)
    {
        if (!IsReady) throw new InvalidOperationException("Servidor de transcrição ainda carregando o modelo");
        using var form = new MultipartFormDataContent();
        var file = new ByteArrayContent(wav);
        file.Headers.ContentType = new("audio/wav");
        form.Add(file, "file", "audio.wav");
        form.Add(new StringContent("json"), "response_format");
        form.Add(new StringContent("0.0"), "temperature");
        form.Add(new StringContent(language), "language");
        if (prompt.Length > 0) form.Add(new StringContent(prompt), "prompt");

        using var resp = await _http.PostAsync("inference", form);
        var body = await resp.Content.ReadAsStringAsync();
        if (!resp.IsSuccessStatusCode) throw new InvalidOperationException($"Servidor respondeu {(int)resp.StatusCode}: {body}");
        return (JsonNode.Parse(body)?["text"]?.GetValue<string>() ?? "").Trim();
    }
}
