using Avalonia;
using System;

namespace AppName.App;

sealed class Program
{
    // Initialization code. Don't use any Avalonia, third-party APIs or any
    // SynchronizationContext-reliant code before AppMain is called: things aren't
    // initialized yet and stuff might break.

    /// A deep-link URL the app was launched with (appname://… or the https twin),
    /// consumed by the shell once shown — the "deep links land in an inbox" rule:
    /// external entry points never mutate navigation directly.
    public static string? LaunchUrl { get; private set; }

    [STAThread]
    public static void Main(string[] args)
    {
        LaunchUrl = Array.Find(args, a =>
            a.StartsWith("appname:", StringComparison.OrdinalIgnoreCase)
            || a.StartsWith("https://your-domain.example", StringComparison.OrdinalIgnoreCase));
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    // Avalonia configuration, don't remove; also used by visual designer.
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
