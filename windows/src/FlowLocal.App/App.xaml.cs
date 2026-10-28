using System;
using System.Linq;
using System.Threading;
using System.Windows;
using FlowLocal.Core;

namespace FlowLocal.App;

public partial class App : Application
{
    private Mutex? _single;
    private EventWaitHandle? _openHubSignal;
    private KeyboardHook? _hook;
    private DictationController? _controller;
    private TrayIcon? _tray;
    private HubWindow? _hub;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // One instance only; a second launch just asks the first one to show its Hub.
        _single = new Mutex(true, "FlowLocal.SingleInstance", out var first);
        _openHubSignal = new EventWaitHandle(false, EventResetMode.AutoReset, "FlowLocal.OpenHub");
        if (!first) { _openHubSignal.Set(); Shutdown(); return; }
        new Thread(() =>
        {
            while (_openHubSignal.WaitOne()) Dispatcher.BeginInvoke(OpenHub);
        }) { IsBackground = true }.Start();

        DispatcherUnhandledException += (_, args) =>
        {
            Log.Write("unhandled: " + args.Exception);
            args.Handled = true;
        };

        Theme.Apply();
        Log.Write($"launch: v{typeof(App).Assembly.GetName().Version} os={Environment.OSVersion.Version} dictationKey={Settings.Current.Hotkey} commandKey={Settings.Current.CommandHotkey ?? "off"}");

        _hook = new KeyboardHook();
        _controller = new DictationController(_hook);
        _tray = new TrayIcon(OpenHub, Quit);
        _controller.StatusChanged += s => Dispatcher.BeginInvoke(() => _tray.SetStatus(s));
        _controller.RecordingChanged += on => Dispatcher.BeginInvoke(() => _tray.SetRecording(on));
        _tray.SetStatus(_controller.Status);
        _ = _controller.StartAsync();

        // Started by the "open at login" entry: stay in the tray.
        if (Settings.Current.OpenHubOnStart && !e.Args.Contains("--tray")) OpenHub();
    }

    public void OpenHub()
    {
        if (_controller is null) return;
        if (_hub is null || !_hub.IsLoaded)
        {
            _hub = new HubWindow(_controller);
            _hub.Closed += (_, _) => _hub = null;
        }
        _hub.Show();
        _hub.WindowState = WindowState.Normal;
        _hub.Activate();
    }

    private void Quit()
    {
        _hook?.Dispose();
        _controller?.Shutdown();
        _tray?.Dispose();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _controller?.Shutdown();
        _tray?.Dispose();
        base.OnExit(e);
    }
}
