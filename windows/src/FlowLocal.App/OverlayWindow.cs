using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace FlowLocal.App;

/// <summary>Small floating pill near the bottom of the screen showing the dictation state. Never takes focus.</summary>
internal sealed class OverlayWindow : Window
{
    public static readonly Color Red = Color.FromRgb(0xFF, 0x45, 0x3A), Blue = Color.FromRgb(0x0A, 0x84, 0xFF),
        Orange = Color.FromRgb(0xFF, 0x9F, 0x0A), Purple = Color.FromRgb(0xBF, 0x5A, 0xF2),
        Teal = Color.FromRgb(0x30, 0xB0, 0xC7), Gray = Color.FromRgb(0x8E, 0x8E, 0x93);

    private readonly TextBlock _label = new() { Foreground = Brushes.White, FontSize = 13, FontWeight = FontWeights.Medium, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly Ellipse _dot = new() { Width = 10, Height = 10, Margin = new Thickness(0, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center };
    private readonly DispatcherTimer _hideTimer = new();

    public OverlayWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        Focusable = false;
        SizeToContent = SizeToContent.WidthAndHeight;
        MaxWidth = 460;

        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(_dot);
        row.Children.Add(_label);
        Content = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0xE6, 0x1C, 0x1C, 0x1E)),
            CornerRadius = new CornerRadius(18),
            Padding = new Thickness(16, 9, 18, 9),
            Margin = new Thickness(8),
            Child = row,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 12, ShadowDepth = 2, Opacity = 0.35 },
        };
        _hideTimer.Tick += (_, _) => { _hideTimer.Stop(); Hide(); };
        SourceInitialized += (_, _) =>
        {
            // No activation, not in Alt-Tab, and mouse clicks pass through.
            var h = new WindowInteropHelper(this).Handle;
            NativeMethods.SetWindowLong(h, NativeMethods.GWL_EXSTYLE,
                NativeMethods.GetWindowLong(h, NativeMethods.GWL_EXSTYLE) |
                NativeMethods.WS_EX_NOACTIVATE | NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_TRANSPARENT);
        };
    }

    public void Show(string text, Color color)
    {
        Dispatcher.BeginInvoke(() =>
        {
            _hideTimer.Stop();
            _label.Text = text;
            _dot.Fill = new SolidColorBrush(color);
            if (!IsVisible) Show();
            UpdateLayout();
            var area = SystemParameters.WorkArea;
            Left = area.Left + (area.Width - ActualWidth) / 2;
            Top = area.Bottom - ActualHeight - 36;
        });
    }

    public void SetLevel(float level) => Dispatcher.BeginInvoke(() => _dot.Opacity = 0.45 + level * 0.55);

    /// <summary>Hides now, or after <paramref name="afterMs"/> milliseconds.</summary>
    public void Hide(int afterMs = 0) => Dispatcher.BeginInvoke(() =>
    {
        _hideTimer.Stop();
        if (afterMs <= 0) { if (IsVisible) base.Hide(); return; }
        _hideTimer.Interval = TimeSpan.FromMilliseconds(afterMs);
        _hideTimer.Start();
    });
}
