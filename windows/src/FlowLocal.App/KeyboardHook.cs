using System;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using FlowLocal.Core;

namespace FlowLocal.App;

/// <summary>
/// Global push-to-talk via a low-level keyboard hook. Keys are never swallowed. Handlers are posted to the
/// dispatcher so the hook callback returns immediately (Windows drops hooks that take more than ~300 ms).
/// </summary>
internal sealed class KeyboardHook : IDisposable
{
    public enum Mode { Dictation, Command }

    public event Action<Mode>? Pressed;
    public event Action<Mode>? Released;
    public event Action? Cancel;
    /// <summary>Another key was pressed while the hotkey was held: it was a shortcut (Ctrl+C…), not dictation.</summary>
    public event Action? Chord;

    private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;
    private readonly NativeMethods.LowLevelKeyboardProc _proc;   // kept in a field so the GC cannot collect it
    private IntPtr _hook;
    private Mode? _active;

    public KeyboardHook() { _proc = Callback; }

    public void Start()
    {
        if (_hook != IntPtr.Zero) return;
        _hook = NativeMethods.SetWindowsHookEx(NativeMethods.WH_KEYBOARD_LL, _proc, NativeMethods.GetModuleHandle(null), 0);
        Log.Write(_hook == IntPtr.Zero ? $"keyboard hook FAILED (error {Marshal.GetLastWin32Error()})" : "keyboard hook installed");
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero) NativeMethods.UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }

    private IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var kb = Marshal.PtrToStructure<NativeMethods.KBDLLHOOKSTRUCT>(lParam);
            // Ignore events we inject ourselves (Ctrl+V, Ctrl+C).
            if ((kb.flags & NativeMethods.LLKHF_INJECTED) == 0)
            {
                var msg = wParam.ToInt32();
                var down = msg is NativeMethods.WM_KEYDOWN or NativeMethods.WM_SYSKEYDOWN;
                var up = msg is NativeMethods.WM_KEYUP or NativeMethods.WM_SYSKEYUP;
                if (down || up) Handle((int)kb.vkCode, down);
            }
        }
        return NativeMethods.CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private void Handle(int vk, bool down)
    {
        var s = Settings.Current;
        Mode? mode = vk == s.DictationKey.Vk ? Mode.Dictation : vk == s.CommandKey?.Vk ? Mode.Command : null;

        if (mode is { } m)
        {
            if (down && _active is null)            // key auto-repeat keeps sending "down"; only the first counts
            {
                _active = m;
                Post(() => Pressed?.Invoke(m));
            }
            else if (!down && _active == m)
            {
                _active = null;
                Post(() => Released?.Invoke(m));
            }
        }
        else if (down)
        {
            if (vk == 0x1B) Post(() => Cancel?.Invoke());
            else if (_active is not null) Post(() => Chord?.Invoke());
        }
    }

    private void Post(Action a) => _dispatcher.BeginInvoke(a);
}
