namespace FlowLocal.Core;

public enum AppCategory { Email, Work, Personal, Other }

public static class AppCategories
{
    public static string Key(this AppCategory c) => c.ToString().ToLowerInvariant();

    public static string Title(this AppCategory c) => c switch
    {
        AppCategory.Email => "E-mail",
        AppCategory.Work => "Mensagens de trabalho",
        AppCategory.Personal => "Mensagens pessoais",
        _ => "Outros",
    };

    public static string Examples(this AppCategory c) => c switch
    {
        AppCategory.Email => "Outlook",
        AppCategory.Work => "Slack, Teams, Zoom",
        AppCategory.Personal => "WhatsApp, Telegram, Discord, Signal",
        _ => "Todos os demais apps",
    };

    /// <summary>Category from the foreground process name (without .exe).</summary>
    public static AppCategory FromProcess(string? processName) => (processName ?? "").ToLowerInvariant() switch
    {
        "outlook" or "olk" or "thunderbird" or "hxoutlook" => AppCategory.Email,
        "slack" or "teams" or "ms-teams" or "zoom" or "linear" => AppCategory.Work,
        "whatsapp" or "whatsapp.root" or "telegram" or "discord" or "signal" => AppCategory.Personal,
        _ => AppCategory.Other,
    };

    public static Tone GetTone(this AppCategory c, Settings s) =>
        s.Tones.TryGetValue(c.Key(), out var id) && Enum.TryParse<Tone>(id, true, out var t) ? t : Tone.Standard;
}

public enum Tone { Standard, Formal, Casual, Concise }

public static class Tones
{
    public static string Title(this Tone t) => t switch
    {
        Tone.Formal => "Formal", Tone.Casual => "Casual", Tone.Concise => "Conciso", _ => "Padrão",
    };

    /// <summary>Extra instruction appended to the polish prompt.</summary>
    public static string? Instruction(this Tone t) => t switch
    {
        Tone.Formal => "Use tom formal e profissional, com maiúsculas e pontuação completas.",
        Tone.Casual => "Use tom casual e natural, frases curtas; em mensagens de uma frase, dispense o ponto final.",
        Tone.Concise => "Seja conciso: elimine redundâncias e rodeios, sem perder nenhuma informação.",
        _ => null,
    };
}
