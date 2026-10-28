using System;
using System.Threading.Tasks;
using System.Windows.Automation;
using System.Windows.Automation.Text;
using FlowLocal.Core;

namespace FlowLocal.App;

/// <summary>Reads the selection and the text around the caret through UI Automation (no extra permission on Windows).</summary>
internal static class UiaContext
{
    /// <summary>Selected text in the focused control; falls back to copying it. Call on the UI thread.</summary>
    public static string ReadSelection(int heldHotkeyVk)
    {
        var viaUia = Run(() =>
        {
            var el = AutomationElement.FocusedElement;
            if (el is null || el.Current.IsPassword) return "";
            if (el.TryGetCurrentPattern(TextPattern.Pattern, out var p))
            {
                var ranges = ((TextPattern)p).GetSelection();
                if (ranges.Length > 0) return ranges[0].GetText(-1);
            }
            return "";
        }, "");
        return viaUia.Length > 0 ? viaUia : TextInserter.CopySelection(heldHotkeyVk);
    }

    /// <summary>Window title plus up to 600 chars before and 200 after the caret in the focused field.</summary>
    public static ScreenContext ReadField(ForegroundInfo fg)
    {
        var ctx = new ScreenContext { AppName = fg.ProcessName, WindowTitle = fg.Title };
        var (before, after) = Run(() =>
        {
            var el = AutomationElement.FocusedElement;
            if (el is null || el.Current.IsPassword) return ("", "");

            if (el.TryGetCurrentPattern(TextPattern.Pattern, out var tp))
            {
                var pattern = (TextPattern)tp;
                var sel = pattern.GetSelection();
                if (sel.Length > 0)
                {
                    var b = sel[0].Clone();
                    b.MoveEndpointByRange(TextPatternRangeEndpoint.End, b, TextPatternRangeEndpoint.Start);   // collapse to the caret
                    b.MoveEndpointByUnit(TextPatternRangeEndpoint.Start, TextUnit.Character, -600);
                    var a = sel[0].Clone();
                    a.MoveEndpointByRange(TextPatternRangeEndpoint.Start, a, TextPatternRangeEndpoint.End);
                    a.MoveEndpointByUnit(TextPatternRangeEndpoint.End, TextUnit.Character, 200);
                    return (b.GetText(-1), a.GetText(-1));
                }
            }
            if (el.TryGetCurrentPattern(ValuePattern.Pattern, out var vp))
            {
                var value = ((ValuePattern)vp).Current.Value ?? "";
                return (value.Length > 600 ? value[^600..] : value, "");   // no caret information: assume the end
            }
            return ("", "");
        }, ("", ""));
        ctx.Before = before;
        ctx.After = after;
        return ctx;
    }

    /// <summary>UI Automation can hang on a busy target app; never wait more than 400 ms for it.</summary>
    private static T Run<T>(Func<T> work, T fallback = default!)
    {
        try
        {
            var task = Task.Run(work);
            return task.Wait(400) ? task.Result : fallback;
        }
        catch (Exception e) { Log.Write($"uia failed: {e.GetBaseException().Message}"); return fallback; }
    }
}
