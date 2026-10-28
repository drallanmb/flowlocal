using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace FlowLocal.App;

/// <summary>Tiny helpers so the Hub pages can be built in code with theme-aware (dynamic) brushes.</summary>
internal static class Ui
{
    public static TextBlock Title(string text) => new() { Text = text, Style = (Style)Application.Current.FindResource("Title") };
    public static TextBlock Muted(string text) => new() { Text = text, Style = (Style)Application.Current.FindResource("Muted") };
    public static TextBlock Faint(string text) => new() { Text = text, Style = (Style)Application.Current.FindResource("Faint") };

    public static T Themed<T>(this T el, DependencyProperty property, string brushKey) where T : FrameworkElement
    {
        el.SetResourceReference(property, brushKey);
        return el;
    }

    /// <summary>Flat rounded container with the subtle card fill.</summary>
    public static Border Card(UIElement child, double padding = 14) =>
        new Border { CornerRadius = new CornerRadius(10), Padding = new Thickness(padding), Child = child }.Themed(Border.BackgroundProperty, "CardBrush");

    public static Border Divider() =>
        new Border { Height = 1, Margin = new Thickness(0, 10, 0, 10) }.Themed(Border.BackgroundProperty, "LineBrush");

    /// <summary>Scrollable page: header, then content in a centred column (max 680 px).</summary>
    public static ScrollViewer Page(string title, string subtitle, params UIElement[] content)
    {
        var column = new StackPanel { MaxWidth = 680, Margin = new Thickness(32, 30, 32, 32), HorizontalAlignment = HorizontalAlignment.Center };
        column.Children.Add(Title(title));
        if (subtitle.Length > 0) { var m = Muted(subtitle); m.Margin = new Thickness(0, 4, 0, 18); column.Children.Add(m); }
        else column.Children.Add(new Border { Height = 18 });
        foreach (var c in content) column.Children.Add(c);
        return new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = column, HorizontalContentAlignment = HorizontalAlignment.Stretch };
    }

    /// <summary>Label + detail on the left, a control on the right.</summary>
    public static Grid Row(string label, string detail, UIElement control)
    {
        var g = new Grid { Margin = new Thickness(0, 6, 0, 6) };
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel { Margin = new Thickness(0, 0, 16, 0) };
        left.Children.Add(new TextBlock { Text = label, FontSize = 13.5 });
        if (detail.Length > 0) left.Children.Add(Muted(detail));
        g.Children.Add(left);
        Grid.SetColumn(control, 1);
        control.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        g.Children.Add(control);
        return g;
    }

    public static StackPanel Section(string title, params UIElement[] rows)
    {
        var p = new StackPanel { Margin = new Thickness(0, 0, 0, 22) };
        p.Children.Add(Faint(title));
        var inner = new StackPanel { Margin = new Thickness(0, 0, 0, 0) };
        foreach (var r in rows) inner.Children.Add(r);
        var card = Card(inner);
        card.Margin = new Thickness(0, 6, 0, 0);
        p.Children.Add(card);
        return p;
    }

    public static Button Link(string text, Action onClick)
    {
        var b = new Button { Content = text };
        b.Click += (_, _) => onClick();
        return b;
    }
}
