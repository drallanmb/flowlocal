using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using Microsoft.Win32;

namespace FlowLocal.App;

/// <summary>The FlowLocal mark (an "L" emitting sound waves) drawn in code for the tray, in either theme.</summary>
internal static class AppIconArt
{
    /// <summary>Whether the taskbar uses the light theme (so the glyph must be dark).</summary>
    public static bool TaskbarIsLight()
    {
        try { return Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0) is int v && v == 1; }
        catch { return false; }
    }

    /// <summary>2 waves at rest, 3 while recording.</summary>
    public static Icon Tray(int arcs)
    {
        const int size = 64;   // drawn large, scaled down by the shell
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            var color = TaskbarIsLight() ? Color.FromArgb(28, 28, 30) : Color.White;
            var u = size / 18f;
            using var pen = new Pen(color, 2.4f * u) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
            // The L (GDI+ y axis points down).
            g.DrawLines(pen, new[] { new PointF(4 * u, 2.5f * u), new PointF(4 * u, 14.8f * u), new PointF(10.5f * u, 14.8f * u) });
            var radii = new[] { 2.8f, 5.4f, 8.0f };
            for (var i = 0; i < arcs; i++)
            {
                using var arcPen = new Pen(Color.FromArgb((int)(255 * (1 - i * 0.22)), color), 1.6f * u) { StartCap = LineCap.Round, EndCap = LineCap.Round };
                var r = radii[i] * u;
                var cx = 6.1f * u; var cy = 12.7f * u;
                g.DrawArc(arcPen, cx - r, cy - r, 2 * r, 2 * r, -85, 80);   // quarter facing up-right
            }
        }
        var hIcon = bmp.GetHicon();
        var icon = (Icon)Icon.FromHandle(hIcon).Clone();
        NativeMethods.DestroyIcon(hIcon);
        return icon;
    }
}
