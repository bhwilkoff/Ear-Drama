using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Styling;
using Avalonia.Threading;
using AppName.App.ViewModels;
using AppName.App.Views;

namespace AppName.HeadlessTests;

/// Render the WHOLE shell to PNGs — the artifacts a session Reads to see the
/// Windows UI from the Mac. Two lessons baked in:
/// - Render the whole shell at a NARROW width as well as a generous one; single
///   views rendered at generous sizes hide the clipping and wrapping bugs an owner
///   sees on a small laptop.
/// - Capture BOTH themes; accent-derivation bugs (washed-out brand color) only show
///   in dark.
public class ShellSnapshots
{
    private static string ArtifactDir()
    {
        var d = Environment.GetEnvironmentVariable("APPNAME_ARTIFACTS")
                ?? Path.Combine(AppContext.BaseDirectory, "artifacts");
        Directory.CreateDirectory(d);
        return d;
    }

    [AvaloniaTheory]
    [InlineData(1180, 760, "Light")]
    [InlineData(1180, 760, "Dark")]
    [InlineData(900, 680, "Light")]   // the narrow floor (MinWidth/MinHeight)
    [InlineData(900, 680, "Dark")]
    public void Shell_renders(int w, int h, string theme)
    {
        var win = new MainWindow
        {
            DataContext = new MainWindowViewModel(),
            Width = w,
            Height = h,
            RequestedThemeVariant = theme == "Dark" ? ThemeVariant.Dark : ThemeVariant.Light,
        };
        win.Show();
        Dispatcher.UIThread.RunJobs();

        var frame = win.CaptureRenderedFrame();
        Assert.NotNull(frame);
        frame!.Save(Path.Combine(ArtifactDir(), $"shell-{w}x{h}-{theme}.png"));
    }
}
