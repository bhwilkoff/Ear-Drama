using Avalonia;
using Avalonia.Headless;
using AppName.HeadlessTests;

[assembly: Avalonia.Headless.AvaloniaTestApplication(typeof(TestAppBuilder))]

namespace AppName.HeadlessTests;

/// The headless app builder — the observability spine of the whole platform.
/// UseSkia + UseHeadlessDrawing=false render REAL pixels to a bitmap on any OS, so
/// a PNG of the Windows UI can be captured from a Mac and Read. (The attribute
/// lives in the Avalonia.Headless namespace, NOT Avalonia.Headless.XUnit.)
public sealed class TestAppBuilder
{
    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<AppName.App.App>()
            .UseSkia()
            .WithInterFont()
            .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false });
}
