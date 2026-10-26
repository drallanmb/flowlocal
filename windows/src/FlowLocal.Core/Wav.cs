namespace FlowLocal.Core;

public static class Wav
{
    public const int SampleRate = 16_000;

    /// <summary>Wraps 16-bit mono PCM at 16 kHz (what whisper expects) in a RIFF/WAVE header.</summary>
    public static byte[] Encode(ReadOnlySpan<byte> pcm16Mono)
    {
        using var ms = new MemoryStream(44 + pcm16Mono.Length);
        using var w = new BinaryWriter(ms);
        w.Write("RIFF"u8); w.Write(36 + pcm16Mono.Length);
        w.Write("WAVE"u8);
        w.Write("fmt "u8); w.Write(16); w.Write((short)1); w.Write((short)1);
        w.Write(SampleRate); w.Write(SampleRate * 2); w.Write((short)2); w.Write((short)16);
        w.Write("data"u8); w.Write(pcm16Mono.Length);
        w.Write(pcm16Mono);
        return ms.ToArray();
    }

    /// <summary>Peak amplitude (0..1) of 16-bit PCM, to tell a silent microphone from a quiet one.</summary>
    public static float Peak(ReadOnlySpan<byte> pcm16Mono)
    {
        var peak = 0;
        for (var i = 0; i + 1 < pcm16Mono.Length; i += 2)
            peak = Math.Max(peak, Math.Abs((short)(pcm16Mono[i] | (pcm16Mono[i + 1] << 8))));
        return peak / 32768f;
    }
}
