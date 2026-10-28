using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using FlowLocal.Core;
using Microsoft.Win32;
using NAudio.Wave;

namespace FlowLocal.App;

internal static class HubPages
{
    // MARK: Home: setup checklist + history

    public static UIElement Home(DictationController controller)
    {
        var setup = new StackPanel();
        var stats = Ui.Faint("");
        var search = new TextBox { Margin = new Thickness(0, 6, 0, 14) };
        var list = new StackPanel();

        async void RefreshSetup()
        {
            setup.Children.Clear();
            var rows = await SetupChecks.RunAsync(controller);
            setup.Children.Clear();
            if (rows.All(r => r.Ok || r.Optional)) return;   // everything needed is ready: hide the card
            var inner = new StackPanel();
            inner.Children.Add(new TextBlock { Text = "Configuração inicial", FontWeight = FontWeights.SemiBold, FontSize = 14 });
            inner.Children.Add(Ui.Muted("Cada item fica ✓ quando estiver pronto. Faça de cima para baixo."));
            foreach (var r in rows)
            {
                var line = new Grid { Margin = new Thickness(0, 9, 0, 0) };
                line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(26) });
                line.ColumnDefinitions.Add(new ColumnDefinition());
                line.Children.Add(new TextBlock { Text = r.Ok ? "✓" : r.Optional ? "○" : "✗", FontSize = 15, Foreground = r.Ok ? Brushes.SeaGreen : r.Optional ? Brushes.DarkOrange : Brushes.IndianRed });
                var text = new StackPanel();
                text.Children.Add(new TextBlock { Text = r.Title + (r.Optional ? " (opcional)" : ""), FontSize = 13.5 });
                if (!r.Ok) text.Children.Add(Ui.Muted(r.Help));
                Grid.SetColumn(text, 1);
                line.Children.Add(text);
                inner.Children.Add(line);
            }
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 14, 0, 0) };
            var again = Ui.Link("Verificar de novo", () => { _ = controller.StartWhisperAsync().ContinueWith(_ => Application.Current.Dispatcher.BeginInvoke(RefreshSetup)); RefreshSetup(); });
            var folder = Ui.Link("Abrir pasta de dados", () => Process.Start(new ProcessStartInfo(AppPaths.Support) { UseShellExecute = true }));
            folder.Margin = new Thickness(8, 0, 0, 0);
            buttons.Children.Add(again);
            buttons.Children.Add(folder);
            inner.Children.Add(buttons);
            var card = Ui.Card(inner, 16);
            card.Margin = new Thickness(0, 0, 0, 18);
            setup.Children.Add(card);
        }

        void Rebuild()
        {
            var all = History.Load();
            stats.Text = $"{all.Count} ditados  ·  {all.Sum(e => e.Words)} palavras  ·  " +
                         (all.Sum(e => e.Seconds) > 1 ? (int)(all.Sum(e => e.Words) / (all.Sum(e => e.Seconds) / 60)) : 0) + " palavras/min";
            var q = search.Text.Trim();
            var shown = q.Length == 0 ? all : all.Where(e => e.Text.Contains(q, StringComparison.CurrentCultureIgnoreCase) || e.App.Contains(q, StringComparison.CurrentCultureIgnoreCase)).ToList();
            list.Children.Clear();
            if (shown.Count == 0)
            {
                var empty = Ui.Muted(all.Count == 0 ? "Nada por aqui ainda. Faça seu primeiro ditado!" : $"Nenhum resultado para “{q}”.");
                empty.Margin = new Thickness(0, 30, 0, 0);
                empty.HorizontalAlignment = HorizontalAlignment.Center;
                list.Children.Add(empty);
                return;
            }
            string? lastDay = null;
            foreach (var e in shown)
            {
                var local = e.At.ToLocalTime();
                var day = local.Date == DateTime.Today ? "Hoje" : local.Date == DateTime.Today.AddDays(-1) ? "Ontem" : local.ToString("D", CultureInfo.CurrentCulture);
                if (day != lastDay)
                {
                    var h = Ui.Faint(day);
                    h.Margin = new Thickness(0, lastDay is null ? 0 : 18, 0, 6);
                    list.Children.Add(h);
                    lastDay = day;
                }
                list.Children.Add(HistoryRow(e));
            }
        }

        search.TextChanged += (_, _) => Rebuild();
        void OnChanged() => Application.Current.Dispatcher.BeginInvoke(Rebuild);
        History.Changed += OnChanged;

        var page = Ui.Page("Início", $"Segure {Settings.Current.DictationKey.Title}, fale e solte. Um toque rápido liga o modo mãos livres.",
            setup, stats, search, list);
        page.Unloaded += (_, _) => History.Changed -= OnChanged;
        RefreshSetup();
        Rebuild();
        // Re-check the setup card every few seconds while the page is visible (model loading, Ollama starting…).
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        timer.Tick += (_, _) => { if (page.IsVisible) RefreshSetup(); else timer.Stop(); };
        timer.Start();
        return page;
    }

    private static UIElement HistoryRow(HistoryEntry e)
    {
        var g = new Grid { Margin = new Thickness(0, 0, 0, 12) };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(64) });
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.Children.Add(Ui.Faint(e.At.ToLocalTime().ToString("t", CultureInfo.CurrentCulture)));

        var text = new StackPanel();
        text.Children.Add(new TextBlock { Text = e.Text, TextWrapping = TextWrapping.Wrap, FontSize = 14 });
        if (e.IsCommand)
        {
            var c = Ui.Muted($"Comando: “{e.Raw}”");
            c.Foreground = (Brush)Application.Current.FindResource("AccentBrush");
            text.Children.Add(c);
        }
        if (e.App.Length > 0) text.Children.Add(Ui.Faint($"{e.App} · {e.Words} palavras"));
        Grid.SetColumn(text, 1);
        g.Children.Add(text);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        var copy = new Button { Content = "", FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), Style = (Style)Application.Current.FindResource("IconButton"), ToolTip = "Copiar" };
        copy.Click += (_, _) => { try { Clipboard.SetText(e.Text); } catch { } };
        var del = new Button { Content = "", FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), Style = (Style)Application.Current.FindResource("IconButton"), ToolTip = "Apagar" };
        del.Click += (_, _) => History.Remove(new HashSet<string> { e.Id });
        buttons.Children.Add(copy);
        buttons.Children.Add(del);
        Grid.SetColumn(buttons, 2);
        g.Children.Add(buttons);
        return g;
    }

    // MARK: Dictionary

    public static UIElement Dictionary()
    {
        var items = DictionaryStore.Load();
        var from = new TextBox { Tag = "Palavra ou como você fala" };
        var to = new TextBox { Tag = "Escrever como (opcional)", Margin = new Thickness(8, 0, 8, 0) };
        var add = new Button { Content = "Adicionar" };
        var list = new StackPanel { Margin = new Thickness(0, 14, 0, 0) };

        void Rebuild()
        {
            list.Children.Clear();
            if (items.Count == 0) list.Children.Add(Ui.Muted("Sem palavras ainda. Ex.: “claude code” → “Claude Code”."));
            foreach (var item in items.ToList())
            {
                var row = new Grid { Margin = new Thickness(0, 4, 0, 4) };
                row.ColumnDefinitions.Add(new ColumnDefinition());
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
                row.ColumnDefinitions.Add(new ColumnDefinition());
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var f = new TextBox { Text = item.From };
                var t = new TextBox { Text = item.To };
                f.LostFocus += (_, _) => { item.From = f.Text; DictionaryStore.Save(items); };
                t.LostFocus += (_, _) => { item.To = t.Text; DictionaryStore.Save(items); };
                var arrow = new TextBlock { Text = "→", HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
                var del = new Button { Content = "", FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), Style = (Style)Application.Current.FindResource("IconButton") };
                del.Click += (_, _) => { items.Remove(item); DictionaryStore.Save(items); Rebuild(); };
                Grid.SetColumn(arrow, 1); Grid.SetColumn(t, 2); Grid.SetColumn(del, 3);
                row.Children.Add(f); row.Children.Add(arrow); row.Children.Add(t); row.Children.Add(del);
                list.Children.Add(row);
            }
        }

        add.Click += (_, _) =>
        {
            var f = from.Text.Trim();
            if (f.Length == 0) return;
            items.RemoveAll(i => string.Equals(i.From, f, StringComparison.CurrentCultureIgnoreCase));
            items.Add(new DictEntry { From = f, To = to.Text.Trim().Length == 0 ? f : to.Text.Trim() });
            items = items.OrderBy(i => i.From, StringComparer.CurrentCultureIgnoreCase).ToList();
            DictionaryStore.Save(items);
            from.Text = to.Text = "";
            Rebuild();
        };

        var bar = new Grid();
        bar.ColumnDefinitions.Add(new ColumnDefinition());
        bar.ColumnDefinitions.Add(new ColumnDefinition());
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(to, 1); Grid.SetColumn(add, 2);
        bar.Children.Add(from); bar.Children.Add(to); bar.Children.Add(add);
        Rebuild();
        var labels = new Grid();
        labels.ColumnDefinitions.Add(new ColumnDefinition());
        labels.ColumnDefinitions.Add(new ColumnDefinition());
        labels.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
        var l2 = Ui.Faint("Escrever como (opcional)"); l2.Margin = new Thickness(8, 0, 0, 0); Grid.SetColumn(l2, 1);
        labels.Children.Add(Ui.Faint("Palavra ou como você fala")); labels.Children.Add(l2);
        var form = new StackPanel(); labels.Margin = new Thickness(0, 0, 0, 6);
        form.Children.Add(labels); form.Children.Add(bar);
        return Ui.Page("Dicionário", "Nomes, siglas e termos que o FlowLocal deve escrever do seu jeito. Eles também orientam o reconhecimento de voz.",
            Ui.Card(form), list);
    }

    // MARK: Snippets

    public static UIElement Snippets()
    {
        var items = SnippetStore.Load();
        var trigger = new TextBox();
        var expansion = new TextBox { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Height = 84, Margin = new Thickness(0, 8, 0, 8), VerticalContentAlignment = VerticalAlignment.Top };
        var add = new Button { Content = "Adicionar snippet", HorizontalAlignment = HorizontalAlignment.Right };
        var list = new StackPanel { Margin = new Thickness(0, 14, 0, 0) };

        void Rebuild()
        {
            list.Children.Clear();
            if (items.Count == 0) list.Children.Add(Ui.Muted("Nenhum snippet. Ex.: “meu e-mail” → seu endereço de e-mail."));
            foreach (var s in items.ToList())
            {
                var body = new StackPanel();
                body.Children.Add(new TextBlock { Text = $"“{s.Trigger}”", FontWeight = FontWeights.SemiBold, FontSize = 14 });
                var m = Ui.Muted(s.Expansion); m.MaxHeight = 80; body.Children.Add(m);
                var del = new Button { Content = "", FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), Style = (Style)Application.Current.FindResource("IconButton"), VerticalAlignment = VerticalAlignment.Top };
                del.Click += (_, _) => { items.Remove(s); SnippetStore.Save(items); Rebuild(); };
                var g = new Grid();
                g.ColumnDefinitions.Add(new ColumnDefinition());
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                Grid.SetColumn(del, 1);
                g.Children.Add(body); g.Children.Add(del);
                var card = Ui.Card(g); card.Margin = new Thickness(0, 0, 0, 8);
                list.Children.Add(card);
            }
        }

        add.Click += (_, _) =>
        {
            if (trigger.Text.Trim().Length == 0 || expansion.Text.Length == 0) return;
            items.RemoveAll(i => string.Equals(i.Trigger, trigger.Text.Trim(), StringComparison.CurrentCultureIgnoreCase));
            items.Add(new Snippet { Trigger = trigger.Text.Trim(), Expansion = expansion.Text });
            SnippetStore.Save(items);
            trigger.Text = expansion.Text = "";
            Rebuild();
        };

        var form = new StackPanel();
        form.Children.Add(Ui.Faint("Quando eu disser… (ex.: meu linkedin)"));
        form.Children.Add(trigger);
        form.Children.Add(expansion);
        form.Children.Add(add);
        Rebuild();
        return Ui.Page("Snippets", "Diga uma frase curta e o FlowLocal cola o texto completo, exatamente como escrito (sem passar pelo LLM).", Ui.Card(form), list);
    }

    // MARK: Style

    public static UIElement Style()
    {
        var rows = new List<UIElement>();
        foreach (var category in Enum.GetValues<AppCategory>())
        {
            var combo = new ComboBox { ItemsSource = Enum.GetValues<Tone>().Select(t => t.Title()).ToList(), Width = 200 };
            combo.SelectedIndex = (int)category.GetTone(Settings.Current);
            combo.SelectionChanged += (_, _) =>
            {
                if (combo.SelectedIndex < 0) return;
                Settings.Current.Tones[category.Key()] = ((Tone)combo.SelectedIndex).ToString();
                Settings.Current.Save();
            };
            var card = Ui.Card(Ui.Row(category.Title(), category.Examples(), combo));
            card.Margin = new Thickness(0, 0, 0, 10);
            rows.Add(card);
        }
        rows.Add(Ui.Faint("O tom padrão só corrige pontuação e hesitações; os demais também reescrevem o registro do texto. Requer o polimento por LLM."));
        return Ui.Page("Estilo", "Escolha o tom do polimento conforme o tipo de app em que você está ditando.", rows.ToArray());
    }

    // MARK: Scratchpad

    public static UIElement Scratchpad()
    {
        var box = new TextBox
        {
            AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontSize = 15, Padding = new Thickness(12),
            VerticalContentAlignment = VerticalAlignment.Top, MinHeight = 380, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Text = File.Exists(AppPaths.Scratchpad) ? File.ReadAllText(AppPaths.Scratchpad) : "",
        };
        box.TextChanged += (_, _) => { try { File.WriteAllText(AppPaths.Scratchpad, box.Text); } catch { } };
        return Ui.Page("Rascunho", "Um bloco de notas para ditar. Clique no texto, segure a tecla de ditado e fale.", box);
    }

    // MARK: Settings

    public static UIElement SettingsPage(DictationController controller)
    {
        var s = Settings.Current;

        ComboBox KeyCombo(bool allowOff, string? current, Action<string?> set)
        {
            var entries = new List<(string? Id, string Title)>();
            if (allowOff) entries.Add((null, "Desligado"));
            entries.AddRange(HotkeyKey.All.Select(k => ((string?)k.Id, k.Title)));
            var c = new ComboBox { ItemsSource = entries.Select(e => e.Title).ToList(), Width = 260 };
            c.SelectedIndex = Math.Max(0, entries.FindIndex(e => e.Id == current));
            c.SelectionChanged += (_, _) => { if (c.SelectedIndex >= 0) { set(entries[c.SelectedIndex].Id); s.Save(); } };
            return c;
        }

        CheckBox Check(bool value, Action<bool> set)
        {
            var c = new CheckBox { IsChecked = value };
            c.Click += (_, _) => { set(c.IsChecked == true); s.Save(); };
            return c;
        }

        TextBox Text(string value, Action<string> set, double width)
        {
            var t = new TextBox { Text = value, Width = width };
            t.LostFocus += (_, _) => { set(t.Text.Trim()); s.Save(); };
            return t;
        }

        var language = new ComboBox { ItemsSource = new[] { "Português", "English", "Español", "Detectar automaticamente" }, Width = 260 };
        var langCodes = new[] { "pt", "en", "es", "auto" };
        language.SelectedIndex = Math.Max(0, Array.IndexOf(langCodes, s.Language));
        language.SelectionChanged += (_, _) => { if (language.SelectedIndex >= 0) { s.Language = langCodes[language.SelectedIndex]; s.Save(); } };

        var models = WhisperServer.InstalledModels().ToList();
        if (!models.Contains(s.WhisperModel)) models.Insert(0, s.WhisperModel);
        var model = new ComboBox { ItemsSource = models, SelectedItem = s.WhisperModel, Width = 260 };
        model.SelectionChanged += (_, _) => { if (model.SelectedItem is string m && m != s.WhisperModel) { s.WhisperModel = m; s.Save(); } };

        var login = new CheckBox { IsChecked = Autostart.IsEnabled };
        login.Click += (_, _) => Autostart.Set(login.IsChecked == true);

        return Ui.Page("Configurações", "Tudo é salvo automaticamente.",
            Ui.Section("Ditado",
                Ui.Row("Tecla de ditado", "Segure para falar, solte para colar. O Windows não expõe a tecla Fn.", KeyCombo(false, s.Hotkey, id => s.Hotkey = id ?? "RightCtrl")),
                Ui.Row("Tecla de comando", "Selecione um texto, segure e diga o que fazer (“traduza para inglês”). Sem seleção, escreve um texto novo.", KeyCombo(true, s.CommandHotkey, id => s.CommandHotkey = id)),
                Ui.Row("Idioma", "Detecção automática erra mais em frases curtas.", language),
                Ui.Row("Remover “hum”, “ãh”", "Tira hesitações antes de colar.", Check(s.CleanFillers, v => s.CleanFillers = v))),
            Ui.Section("Contexto e modos",
                Ui.Row("Mãos livres", "Um toque rápido na tecla mantém a gravação ligada; toque de novo para finalizar. Esc cancela.", Check(s.HandsFree, v => s.HandsFree = v)),
                Ui.Row("Contexto do campo de texto", "Lê o texto ao redor do cursor e o título da janela para acertar nomes, maiúsculas e espaços.", Check(s.FieldContext, v => s.FieldContext = v)),
                Ui.Row("Ler a tela (OCR)", "Reconhece o texto da janela em foco com o OCR do Windows, offline. Exige um pacote de idioma de OCR instalado.", Check(s.ScreenOcr, v => s.ScreenOcr = v))),
            Ui.Section("Modelos locais",
                Ui.Row("Transcrição (whisper.cpp)", $"Arquivos .bin em {AppPaths.Models}", model),
                Ui.Row("Caminho do whisper-server.exe", "Vazio = procurar em %LOCALAPPDATA%\\FlowLocal\\whisper.", Text(s.WhisperServerPath, v => s.WhisperServerPath = v, 260)),
                Ui.Row("Polimento por LLM", "Corrige o texto com um modelo do Ollama.", Check(s.LlmEnabled, v => s.LlmEnabled = v)),
                Ui.Row("Modelo do Ollama", "Ex.: qwen2.5:3b-instruct, llama3.2:3b", Text(s.LlmModel, v => s.LlmModel = v.Length == 0 ? "qwen2.5:3b-instruct" : v, 220))),
            Ui.Section("Geral",
                Ui.Row("Abrir ao iniciar sessão", "O ditado fica sempre disponível, na bandeja.", login),
                Ui.Row("Microfone do Windows", "Ative “Permitir que aplicativos da área de trabalho acessem o microfone”.", Ui.Link("Abrir ajustes", () => Process.Start(new ProcessStartInfo("ms-settings:privacy-microphone") { UseShellExecute = true }))),
                Ui.Row("Diagnóstico", "Teclas, estado da instalação e erros (nunca o texto ditado).", Ui.Link("Abrir log", () => Process.Start(new ProcessStartInfo(AppPaths.LogFile) { UseShellExecute = true }))),
                Ui.Row("Pasta de dados", "Histórico, dicionário, snippets e modelos.", Ui.Link("Mostrar no Explorer", () => Process.Start(new ProcessStartInfo(AppPaths.Support) { UseShellExecute = true })))));
    }
}

/// <summary>"Open at login" through the per-user Run registry key.</summary>
internal static class Autostart
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool IsEnabled
    {
        get { using var k = Registry.CurrentUser.OpenSubKey(KeyPath); return k?.GetValue("FlowLocal") is not null; }
    }

    public static void Set(bool on)
    {
        using var k = Registry.CurrentUser.OpenSubKey(KeyPath, writable: true);
        if (k is null) return;
        if (on) k.SetValue("FlowLocal", $"\"{Environment.ProcessPath}\" --tray");
        else k.DeleteValue("FlowLocal", throwOnMissingValue: false);
    }
}

internal sealed record SetupRow(string Title, bool Ok, string Help, bool Optional = false);

/// <summary>What must be in place for dictation to work, with a hint for each missing piece (the Windows "permission guide").</summary>
internal static class SetupChecks
{
    public static async System.Threading.Tasks.Task<List<SetupRow>> RunAsync(DictationController controller)
    {
        var s = Settings.Current;
        var exe = WhisperServer.FindServerExe(s);
        var model = WhisperServer.ModelPath(s);
        var rows = new List<SetupRow>
        {
            new("Microfone encontrado", WaveInEvent.DeviceCount > 0, "Conecte um microfone e deixe-o como dispositivo de entrada padrão do Windows."),
            new("whisper-server.exe", exe is not null, "Abra o PowerShell na pasta do projeto e rode: .\\windows\\scripts\\setup.ps1 (baixa o whisper.cpp e o modelo)."),
            new("Modelo de voz", File.Exists(model), $"Falta {model}. O setup.ps1 baixa o modelo; ou copie um arquivo .bin para a pasta indicada."),
            new("Servidor de transcrição ativo", controller.Whisper.IsReady, controller.Status),
        };
        if (s.LlmEnabled || s.CommandKey is not null)
        {
            var up = await controller.Llm.IsUpAsync();
            var installed = up ? await controller.Llm.InstalledModelsAsync() : new List<string>();
            var hasModel = installed.Any(m => string.Equals(m, s.LlmModel, StringComparison.OrdinalIgnoreCase) || m.StartsWith(s.LlmModel + ":", StringComparison.OrdinalIgnoreCase));
            rows.Add(new("Ollama ativo", up, "Instale com: winget install Ollama.Ollama. O FlowLocal inicia o servidor sozinho.", Optional: true));
            rows.Add(new($"Modelo {s.LlmModel} no Ollama", hasModel, $"Rode: ollama pull {s.LlmModel}", Optional: true));
        }
        return rows;
    }
}
