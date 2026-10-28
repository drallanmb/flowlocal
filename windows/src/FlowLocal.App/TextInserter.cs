using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using FlowLocal.Core;

namespace FlowLocal.App;

/// <summary>Inserts text into the focused app: clipboard swap + synthetic Ctrl+V, then restores the clipboard.</summary>
internal static class TextInserter
{
    private static readonly string[] Formats =
        { DataFormats.UnicodeText, DataFormats.Html, DataFormats.Rtf, DataFormats.Bitmap, DataFormats.FileDrop };

    /// <summary>Must run on the UI thread (the clipboard needs an STA thread).</summary>
    public static async Task InsertAsync(string text)
    {
        var saved = Snapshot();
        Retry(() => Clipboard.SetDataObject(text, true));
        var ours = NativeMethods.GetClipboardSequenceNumber();

        // Dictating into our own window: paste straight into the focused text box.
        if (ForegroundInfo.Get().IsOwn && Keyboard.FocusedElement is TextBox box) box.Paste();
        else SendCtrl(NativeMethods.VK_V);

        // Give the target app time to read the clipboard before restoring it.
        await Task.Delay(600);
        if (NativeMethods.GetClipboardSequenceNumber() == ours) Restore(saved);   // someone else copied meanwhile: leave it
    }

    /// <summary>Returns the selected text by copying it, then puts the user's clipboard back. Blocks up to ~0.3 s.</summary>
    public static string CopySelection(int heldHotkeyVk)
    {
        var saved = Snapshot();
        Retry(Clipboard.Clear);
        var marker = NativeMethods.GetClipboardSequenceNumber();

        // If the command key is a modifier we are still holding, release it first so the app sees plain Ctrl+C.
        if (heldHotkeyVk is 0xA5 or 0xA1) SendKey((ushort)heldHotkeyVk, up: true);
        SendCtrl(NativeMethods.VK_C);

        var deadline = DateTime.UtcNow.AddMilliseconds(300);
        while (NativeMethods.GetClipboardSequenceNumber() == marker && DateTime.UtcNow < deadline) Thread.Sleep(20);

        var text = "";
        if (NativeMethods.GetClipboardSequenceNumber() != marker)
            try { text = Clipboard.ContainsText() ? Clipboard.GetText() : ""; } catch { }
        Restore(saved);
        return text;
    }

    public static void SendCtrl(ushort key)
    {
        var inputs = new[] { Key(NativeMethods.VK_CONTROL, false), Key(key, false), Key(key, true), Key(NativeMethods.VK_CONTROL, true) };
        var sent = NativeMethods.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<NativeMethods.INPUT>());
        if (sent != inputs.Length) Log.Write($"SendInput sent {sent}/{inputs.Length} (blocked by an elevated window?)");
    }

    private static void SendKey(ushort vk, bool up) =>
        NativeMethods.SendInput(1, new[] { Key(vk, up) }, Marshal.SizeOf<NativeMethods.INPUT>());

    private static NativeMethods.INPUT Key(ushort vk, bool up) => new()
    {
        type = NativeMethods.INPUT_KEYBOARD,
        ki = new NativeMethods.KEYBDINPUT { wVk = vk, dwFlags = up ? NativeMethods.KEYEVENTF_KEYUP : 0 },
    };

    // MARK: Clipboard snapshot

    private static Dictionary<string, object>? Snapshot()
    {
        try
        {
            var data = Clipboard.GetDataObject();
            if (data is null) return null;
            var copy = new Dictionary<string, object>();
            foreach (var f in Formats)
                if (data.GetDataPresent(f) && data.GetData(f) is { } value) copy[f] = value;
            return copy;
        }
        catch { return null; }
    }

    private static void Restore(Dictionary<string, object>? saved)
    {
        try
        {
            if (saved is null || saved.Count == 0) { Retry(Clipboard.Clear); return; }
            var data = new DataObject();
            foreach (var (format, value) in saved) data.SetData(format, value);
            Retry(() => Clipboard.SetDataObject(data, true));
        }
        catch (Exception e) { Log.Write($"clipboard restore failed: {e.Message}"); }
    }

    /// <summary>The clipboard is shared and often briefly locked by other apps; retry a few times.</summary>
    private static void Retry(Action action)
    {
        for (var i = 0; i < 6; i++)
        {
            try { action(); return; }
            catch (COMException) { Thread.Sleep(30); }
        }
        action();
    }
}
