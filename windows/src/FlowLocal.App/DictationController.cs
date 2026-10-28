using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using FlowLocal.Core;

namespace FlowLocal.App;

/// <summary>
/// The dictation pipeline and its hotkey state machine (push-to-talk, hands-free latch, Esc cancel, command mode):
/// hotkey -> record -> whisper -> clean -> snippets -> LLM polish -> fit to the caret -> paste.
/// Everything runs on the UI thread; the heavy steps are awaited.
/// </summary>
internal sealed class DictationController
{
    private readonly KeyboardHook _hook;
    private readonly AudioRecorder _recorder = new();
    private readonly WhisperServer _whisper = new() { OnProcessStarted = ChildProcessJob.Attach };
    private readonly LlmPolisher _llm = new() { OnProcessStarted = ChildProcessJob.Attach };
    private readonly OverlayWindow _overlay = new();

    private KeyboardHook.Mode _mode;
    private ForegroundInfo? _target;
    private ScreenContext? _context;
    private Task<string>? _ocr;
    private string _selection = "";
    private bool _latched, _swallowRelease;
    private int _latchToken;
    private DateTime _pressedAt;

    /// <summary>Status text for the tray tooltip / Hub.</summary>
    public event Action<string>? StatusChanged;
    public event Action<bool>? RecordingChanged;
    public string Status { get; private set; } = "Iniciando…";
    public WhisperServer Whisper => _whisper;
    public LlmPolisher Llm => _llm;

    public DictationController(KeyboardHook hook)
    {
        _hook = hook;
        _hook.Pressed += OnPressed;
        _hook.Released += OnReleased;
        _hook.Cancel += CancelRecording;
        _hook.Chord += () => { if (_recorder.IsRecording && !_latched) CancelRecording(silent: true); };
        _recorder.Level += level => _overlay.SetLevel(level);
        Settings.Changed += OnSettingsChanged;
    }

    public async Task StartAsync()
    {
        _hook.Start();
        if (Settings.Current.LlmEnabled || Settings.Current.CommandKey is not null) _llm.Prepare();
        await StartWhisperAsync();
    }

    public void Shutdown()
    {
        _whisper.Stop();
        _llm.Stop();
    }

    private string _lastModel = Settings.Current.WhisperModel + "|" + Settings.Current.WhisperServerPath;
    private string _lastLlm = $"{Settings.Current.LlmEnabled}|{Settings.Current.LlmModel}|{Settings.Current.CommandHotkey}";

    private void OnSettingsChanged()
    {
        Application.Current.Dispatcher.BeginInvoke(async () =>
        {
            var now = Settings.Current.WhisperModel + "|" + Settings.Current.WhisperServerPath;
            if (now != _lastModel) { _lastModel = now; await StartWhisperAsync(); }
            var llm = $"{Settings.Current.LlmEnabled}|{Settings.Current.LlmModel}|{Settings.Current.CommandHotkey}";
            if (llm != _lastLlm)
            {
                _lastLlm = llm;
                if (Settings.Current.LlmEnabled || Settings.Current.CommandKey is not null) _llm.Prepare();   // preload the (new) model
            }
        });
    }

    /// <summary>(Re)starts whisper-server; also used by the Hub's "check again" button.</summary>
    public async Task StartWhisperAsync()
    {
        SetStatus("Carregando modelo…");
        var error = await _whisper.StartAsync();
        SetStatus(error ?? $"Pronto: segure {Settings.Current.DictationKey.Title}");
        if (error is not null) Log.Write("whisper start: " + error);
    }

    private void SetStatus(string s) { Status = s; StatusChanged?.Invoke(s); }

    // MARK: Hotkey state machine

    private void OnPressed(KeyboardHook.Mode mode)
    {
        if (_recorder.IsRecording && _latched)
        {
            // Second tap while hands-free: finish now and ignore the release that follows.
            _latched = false;
            _swallowRelease = true;
            _ = EndAsync();
            return;
        }
        _pressedAt = DateTime.UtcNow;
        Begin(mode);
    }

    private void OnReleased(KeyboardHook.Mode mode)
    {
        if (_swallowRelease) { _swallowRelease = false; return; }
        if (!_recorder.IsRecording) return;
        if (Settings.Current.HandsFree && (DateTime.UtcNow - _pressedAt).TotalSeconds < 0.3)
        {
            _latched = true;
            _overlay.Show("Mãos livres: toque para finalizar · Esc cancela", OverlayWindow.Red);
            // Safety net: never record forever if the user walks away.
            var token = ++_latchToken;
            Task.Delay(TimeSpan.FromMinutes(10)).ContinueWith(_ => Application.Current.Dispatcher.BeginInvoke(() =>
            {
                if (_latched && _latchToken == token) { _latched = false; _ = EndAsync(); }
            }));
            return;
        }
        _ = EndAsync();
    }

    private void CancelRecording() => CancelRecording(silent: false);

    private void CancelRecording(bool silent)
    {
        if (!_recorder.IsRecording) return;
        _recorder.Stop();
        _latched = false;
        RecordingChanged?.Invoke(false);
        Log.Write(silent ? "recording discarded (key chord)" : "recording cancelled with Esc");
        if (silent) _overlay.Hide();
        else { _overlay.Show("Cancelado", OverlayWindow.Gray); _overlay.Hide(1000); }
    }

    // MARK: Begin / end

    private void Begin(KeyboardHook.Mode mode)
    {
        Log.Write($"begin {mode} whisperReady={_whisper.IsReady}");
        if (!_whisper.IsReady)
        {
            _overlay.Show("Carregando modelo…", OverlayWindow.Orange);
            _overlay.Hide(1500);
            return;
        }
        var s = Settings.Current;
        _mode = mode;
        _target = ForegroundInfo.Get();
        _context = null;
        _ocr = null;
        _selection = "";
        try
        {
            // Read what is selected / around the caret now, while the target app still has focus.
            if (mode == KeyboardHook.Mode.Command) _selection = UiaContext.ReadSelection(s.CommandKey?.Vk ?? 0);
            else
            {
                if (s.FieldContext) _context = UiaContext.ReadField(_target);
                if (s.ScreenOcr && !_target.IsOwn) _ocr = OcrService.RecognizeAsync(_target);
            }
            _recorder.Start();
            RecordingChanged?.Invoke(true);
            _overlay.Show(mode == KeyboardHook.Mode.Command
                ? (_selection.Length == 0 ? "Comando: escrever…" : "Comando: editar…")
                : "Ouvindo…", mode == KeyboardHook.Mode.Command ? OverlayWindow.Teal : OverlayWindow.Red);
        }
        catch (Exception e)
        {
            Log.Write($"recorder start failed: {e.Message}");
            _overlay.Show("Sem microfone", OverlayWindow.Orange);
            _overlay.Hide(2000);
        }
    }

    private async Task EndAsync()
    {
        if (!_recorder.IsRecording) return;
        var pcm = _recorder.Stop();
        RecordingChanged?.Invoke(false);
        var seconds = pcm.Length / 2.0 / Wav.SampleRate;
        var peak = Wav.Peak(pcm);
        Log.Write($"end: {seconds:0.0} s, peak={peak:0.000}");

        if (seconds < 0.4) { _overlay.Hide(); return; }          // accidental tap
        if (peak < 0.002)
        {
            _overlay.Show("Sem sinal do microfone (Configurações › Privacidade › Microfone)", OverlayWindow.Orange);
            _overlay.Hide(4000);
            return;
        }
        _overlay.Show("Transcrevendo…", OverlayWindow.Blue);

        var s = Settings.Current;
        var wav = Wav.Encode(pcm);
        var target = _target ?? ForegroundInfo.Get();
        var app = target.ProcessName;
        var context = _context ?? new ScreenContext { AppName = app };
        var ocr = _ocr;
        var selection = _selection;
        var mode = _mode;

        try
        {
            if (ocr is not null) context.Ocr = await OcrService.ResultAsync(ocr, TimeSpan.FromSeconds(1.5));
            if (!context.IsEmpty)
                Log.Write($"context: field={context.Before.Length}+{context.After.Length} chars, ocr={context.Ocr.Length} chars, terms={context.Terms().Count}");

            if (mode == KeyboardHook.Mode.Command) { await RunCommandAsync(wav, seconds, target, selection, s); return; }

            var raw = await _whisper.TranscribeAsync(wav, s.Language, TextCleaner.PromptHint() + context.WhisperHint());
            var (expanded, usedSnippet) = SnippetStore.Apply(TextCleaner.Clean(raw, s.CleanFillers));
            var polished = expanded;
            // Snippet expansions are verbatim text the user wrote; keep the LLM away from them.
            if (s.LlmEnabled && expanded.Length > 0 && !usedSnippet)
            {
                _overlay.Show("Polindo…", OverlayWindow.Purple);
                var tone = AppCategories.FromProcess(app).GetTone(s);
                polished = await _llm.PolishAsync(expanded, TextCleaner.DictionaryTerms(), tone, context);
            }
            var text = s.FieldContext ? ContextFit.Fit(polished, context, TextCleaner.DictionaryTerms().Concat(context.Terms())) : polished;
            if (text.Length == 0)
            {
                _overlay.Show("Nada detectado", OverlayWindow.Gray);
                _overlay.Hide(1200);
                return;
            }
            Log.Write($"dictation ok: {text.Length} chars");
            History.Append(raw, text, seconds, app);
            await DeliverAsync(text);
        }
        catch (Exception e)
        {
            Log.Write($"dictation failed: {e.Message}");
            _overlay.Show("Falha: " + e.Message, OverlayWindow.Red);
            _overlay.Hide(3500);
        }
    }

    /// <summary>Command mode: the transcript is an instruction applied to the selection (or a prompt, with no selection).</summary>
    private async Task RunCommandAsync(byte[] wav, double seconds, ForegroundInfo target, string selection, Settings s)
    {
        var instruction = (await _whisper.TranscribeAsync(wav, s.Language, TextCleaner.PromptHint())).Trim();
        if (instruction.Length == 0)
        {
            _overlay.Show("Nada detectado", OverlayWindow.Gray);
            _overlay.Hide(1200);
            return;
        }
        _overlay.Show(selection.Length == 0 ? "Escrevendo…" : "Reescrevendo…", OverlayWindow.Teal);
        var result = await _llm.TransformAsync(selection, instruction, TextCleaner.DictionaryTerms());
        History.Append(instruction, result, seconds, target.ProcessName, "command");

        if (ForegroundInfo.Get().Pid == target.Pid) await DeliverAsync(result);   // the selection is still active: pasting replaces it (Ctrl+Z undoes)
        else
        {
            System.Windows.Clipboard.SetText(result);
            _overlay.Show("Foco mudou: resultado copiado", OverlayWindow.Orange);
            _overlay.Hide(3000);
        }
    }

    private async Task DeliverAsync(string text)
    {
        await TextInserter.InsertAsync(text);
        _overlay.Hide();
    }
}
