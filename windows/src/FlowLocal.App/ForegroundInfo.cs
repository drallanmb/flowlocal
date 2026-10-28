using System;
using System.Diagnostics;
using System.Text;

namespace FlowLocal.App;

/// <summary>The window that had focus when the hotkey went down.</summary>
internal sealed record ForegroundInfo(IntPtr Hwnd, uint Pid, string ProcessName, string Title)
{
    public bool IsOwn => Pid == (uint)Environment.ProcessId;

    public static ForegroundInfo Get()
    {
        var hwnd = NativeMethods.GetForegroundWindow();
        NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
        var title = new StringBuilder(256);
        NativeMethods.GetWindowText(hwnd, title, title.Capacity);
        var name = "";
        try { name = Process.GetProcessById((int)pid).ProcessName; } catch { }
        return new ForegroundInfo(hwnd, pid, name, title.ToString());
    }
}
