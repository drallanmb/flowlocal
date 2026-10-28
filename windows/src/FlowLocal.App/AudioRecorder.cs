using System;
using System.IO;
using NAudio.Wave;

namespace FlowLocal.App;

/// <summary>Captures the default microphone as 16 kHz mono 16-bit PCM (what whisper expects).</summary>
internal sealed class AudioRecorder
{
    private WaveInEvent? _input;
    private MemoryStream _buffer = new();
    private readonly object _gate = new();

    public bool IsRecording { get; private set; }
    /// <summary>RMS level 0..1 for UI feedback; raised on a background thread.</summary>
    public event Action<float>? Level;

    public void Start()
    {
        if (IsRecording) return;
        lock (_gate) _buffer = new MemoryStream();
        _input = new WaveInEvent
        {
            DeviceNumber = -1,                       // Windows' default recording device
            WaveFormat = new WaveFormat(16_000, 16, 1),
            BufferMilliseconds = 40,
        };
        _input.DataAvailable += (_, e) =>
        {
            lock (_gate) _buffer.Write(e.Buffer, 0, e.BytesRecorded);
            double sum = 0;
            for (var i = 0; i + 1 < e.BytesRecorded; i += 2)
            {
                var v = (short)(e.Buffer[i] | (e.Buffer[i + 1] << 8)) / 32768.0;
                sum += v * v;
            }
            Level?.Invoke((float)Math.Min(1, Math.Sqrt(sum / Math.Max(e.BytesRecorded / 2, 1)) * 8));
        };
        _input.StartRecording();                     // throws if there is no microphone
        IsRecording = true;
    }

    /// <summary>Stops capture and returns the PCM recorded so far.</summary>
    public byte[] Stop()
    {
        if (!IsRecording) return Array.Empty<byte>();
        IsRecording = false;
        try { _input?.StopRecording(); } catch { }
        _input?.Dispose();
        _input = null;
        lock (_gate) return _buffer.ToArray();
    }
}
