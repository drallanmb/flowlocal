using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace FlowLocal.App;

/// <summary>The Hub: history, dictionary, snippets, style, scratchpad and settings, in a minimal sidebar layout.</summary>
internal sealed class HubWindow : Window
{
    private readonly DictationController _controller;
    private readonly ContentControl _content = new();
    private readonly Dictionary<string, Border> _navItems = new();
    private string _page = "home";

    public HubWindow(DictationController controller)
    {
        _controller = controller;
        Title = "FlowLocal";
        Width = 980; Height = 660; MinWidth = 780; MinHeight = 520;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        this.Themed(BackgroundProperty, "BgBrush");
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");

        try { Icon = BitmapFrame.Create(new Uri("pack://application:,,,/AppIcon.ico")); } catch { }

        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(196) });
        root.ColumnDefinitions.Add(new ColumnDefinition());
        root.Children.Add(BuildSidebar());
        Grid.SetColumn(_content, 1);
        root.Children.Add(_content);
        Content = root;
        Navigate("home");
    }

    private UIElement BuildSidebar()
    {
        var panel = new StackPanel { Margin = new Thickness(10, 22, 10, 12) };
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 0, 0, 22) };
        using (var icon = AppIconArt.Tray(3))
        {
            var src = Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            brand.Children.Add(new Image { Source = src, Width = 22, Height = 22, Margin = new Thickness(0, 0, 8, 0) });
        }
        brand.Children.Add(new TextBlock { Text = "FlowLocal", FontSize = 14.5, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
        panel.Children.Add(brand);

        foreach (var (key, label, glyph) in new[]
        {
            ("home", "Início", ""), ("dictionary", "Dicionário", ""), ("snippets", "Snippets", ""),
            ("style", "Estilo", ""), ("scratchpad", "Rascunho", ""),
        })
            panel.Children.Add(NavItem(key, label, glyph));

        // Settings pinned to the bottom.
        var dock = new DockPanel { LastChildFill = true };
        var bottom = NavItem("settings", "Configurações", "");
        DockPanel.SetDock(bottom, Dock.Bottom);
        bottom.Margin = new Thickness(10, 0, 10, 12);
        dock.Children.Add(bottom);
        dock.Children.Add(panel);
        var host = new Border { Child = dock }.Themed(Border.BackgroundProperty, "SidebarBrush");
        return host;
    }

    private Border NavItem(string key, string label, string glyph)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(new TextBlock { Text = glyph, FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 14, Width = 22, VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(new TextBlock { Text = label, FontSize = 13.5, VerticalAlignment = VerticalAlignment.Center });
        var item = new Border { Child = row, CornerRadius = new CornerRadius(7), Padding = new Thickness(10, 7, 10, 7), Margin = new Thickness(0, 1, 0, 1), Cursor = Cursors.Hand };
        item.MouseLeftButtonUp += (_, _) => Navigate(key);
        _navItems[key] = item;
        return item;
    }

    public void Navigate(string page)
    {
        _page = page;
        foreach (var (key, item) in _navItems)
        {
            if (key == page) item.SetResourceReference(Border.BackgroundProperty, "SelectBrush");
            else item.Background = Brushes.Transparent;
        }
        _content.Content = page switch
        {
            "dictionary" => HubPages.Dictionary(),
            "snippets" => HubPages.Snippets(),
            "style" => HubPages.Style(),
            "scratchpad" => HubPages.Scratchpad(),
            "settings" => HubPages.SettingsPage(_controller),
            _ => HubPages.Home(_controller),
        };
    }
}
