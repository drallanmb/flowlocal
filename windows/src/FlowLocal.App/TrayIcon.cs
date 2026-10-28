using System;
using System.Drawing;
using System.Windows.Forms;
using FlowLocal.Core;

namespace FlowLocal.App;

/// <summary>Notification-area icon with a small menu (the Windows counterpart of the macOS menu bar item).</summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _status = new() { Enabled = false };
    private readonly ToolStripMenuItem _llm = new("Polimento por LLM") { CheckOnClick = true };
    private Icon _idle, _recording;

    public TrayIcon(Action openHub, Action quit)
    {
        _idle = AppIconArt.Tray(2);
        _recording = AppIconArt.Tray(3);
        var menu = new ContextMenuStrip();
        menu.Items.Add(_status);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Abrir Hub", null, (_, _) => openHub());
        menu.Items.Add(_llm);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Sair", null, (_, _) => quit());
        _llm.Click += (_, _) => { Settings.Current.LlmEnabled = _llm.Checked; Settings.Current.Save(); };
        menu.Opening += (_, _) => _llm.Checked = Settings.Current.LlmEnabled;

        _icon = new NotifyIcon { Icon = _idle, Text = "FlowLocal", ContextMenuStrip = menu, Visible = true };
        _icon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) openHub(); };
    }

    public void SetRecording(bool on) => _icon.Icon = on ? _recording : _idle;

    public void SetStatus(string text)
    {
        _status.Text = text.Length > 80 ? text[..80] + "…" : text;
        _icon.Text = ("FlowLocal: " + text) is { Length: > 63 } t ? t[..63] : "FlowLocal: " + text;   // NotifyIcon.Text caps at 63 chars
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
