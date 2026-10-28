using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace FlowLocal.App;

/// <summary>Switches the Hub's brushes between light and dark to match Windows' app theme.</summary>
internal static class Theme
{
    public static bool AppsUseLight()
    {
        try { return Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) is not int v || v == 1; }
        catch { return true; }
    }

    public static void Apply()
    {
        var light = AppsUseLight();
        void Set(string key, string color) => Application.Current.Resources[key] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        Set("BgBrush", light ? "#FFFFFF" : "#1E1E20");
        Set("SidebarBrush", light ? "#F6F6F7" : "#252528");
        Set("FgBrush", light ? "#1C1C1E" : "#F2F2F7");
        Set("MutedBrush", light ? "#6E6E73" : "#A1A1A6");
        Set("FaintBrush", light ? "#A1A1A6" : "#6E6E73");
        Set("CardBrush", light ? "#F2F2F4" : "#2C2C2F");
        Set("LineBrush", light ? "#E5E5EA" : "#3A3A3D");
        Set("AccentBrush", light ? "#5E5CE6" : "#7D7AFF");
        Set("SelectBrush", light ? "#E8E8EC" : "#3A3A3F");
    }
}
