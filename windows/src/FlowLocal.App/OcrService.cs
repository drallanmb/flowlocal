using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Threading.Tasks;
using FlowLocal.Core;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;

namespace FlowLocal.App;

/// <summary>Optional: reads the text of the focused window with the built-in Windows OCR (offline, no permission needed).</summary>
internal static class OcrService
{
    public static async Task<string> RecognizeAsync(ForegroundInfo fg)
    {
        try
        {
            if (!NativeMethods.GetWindowRect(fg.Hwnd, out var r)) return "";
            int w = r.Right - r.Left, h = r.Bottom - r.Top;
            if (w < 200 || h < 150) return "";

            using var bmp = new Bitmap(w, h);
            using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(r.Left, r.Top, 0, 0, new Size(w, h));
            using var ms = new MemoryStream();
            bmp.Save(ms, ImageFormat.Png);
            ms.Position = 0;

            var decoder = await BitmapDecoder.CreateAsync(ms.AsRandomAccessStream());
            using var soft = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
            var engine = OcrEngine.TryCreateFromUserProfileLanguages();
            if (engine is null) { Log.Write("ocr: no OCR language pack installed"); return ""; }
            var text = (await engine.RecognizeAsync(soft)).Text;
            return text.Length > 3000 ? text[..3000] : text;
        }
        catch (Exception e)
        {
            Log.Write($"ocr failed: {e.Message}");
            return "";
        }
    }

    /// <summary>Waits for a background OCR task, giving up after the timeout so dictation is never held up.</summary>
    public static async Task<string> ResultAsync(Task<string> task, TimeSpan timeout) =>
        await Task.WhenAny(task, Task.Delay(timeout)) == task ? task.Result : "";
}
