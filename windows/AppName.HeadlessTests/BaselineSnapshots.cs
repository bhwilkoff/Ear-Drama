using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Styling;
using Avalonia.Threading;
using AppName.App.ViewModels;
using AppName.App.Views;

namespace AppName.HeadlessTests;

/// The baseline-gated renders — the surfaces whose pixels are contractual; a drift
/// fails CI (on Windows only; see VisualBaseline).
///
/// Every render here MUST be deterministic: fixed view-model data, never anything
/// random or live. The scaffold shell is static, so it can be baselined as-is.
///
/// FIRST WINDOWS RUN on a fresh app: there are no committed baselines yet, so run
/// `gh workflow run windows-repl.yml -f update_baselines=true`, download the
/// baselines artifact, and commit it to Baselines/windows/. From then on the gate
/// is armed.
public class BaselineSnapshots
{
    [AvaloniaFact]
    public void Shell_light_matches_baseline()
    {
        var win = new MainWindow
        {
            DataContext = new MainWindowViewModel(),
            Width = 1180,
            Height = 760,
            RequestedThemeVariant = ThemeVariant.Light,
        };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        VisualBaseline.Matches(win, "baseline-shell-light");
    }

    [AvaloniaFact]
    public void Shell_dark_matches_baseline()
    {
        var win = new MainWindow
        {
            DataContext = new MainWindowViewModel(),
            Width = 1180,
            Height = 760,
            RequestedThemeVariant = ThemeVariant.Dark,
        };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        VisualBaseline.Matches(win, "baseline-shell-dark");
    }
}
