using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Media;
using Avalonia.Threading;

namespace AppName.HeadlessTests;

/// Prove the visual gate can SEE — a check that cannot detect a change must die,
/// not report clean. These need no committed baselines: they exercise the
/// comparator directly on captured frames, on COLOURED pixels (the RGBA/BGRA
/// channel-order trap is invisible on grey, where R==G==B).
public class VisualBaselineSelfTest
{
    private static Window ColorWindow(Color color)
    {
        var win = new Window
        {
            Width = 200,
            Height = 120,
            Background = new SolidColorBrush(color),
            Content = new TextBlock { Text = "gate probe", Foreground = Brushes.White, Margin = new Avalonia.Thickness(16) },
        };
        win.Show();
        Dispatcher.UIThread.RunJobs();
        return win;
    }

    [AvaloniaFact]
    public void Identical_renders_report_zero_diff_after_normalize()
    {
        var win = ColorWindow(Color.FromRgb(0xFF, 0x5C, 0x35));
        var a = VisualBaseline.Normalize(win.CaptureRenderedFrame()!);
        var b = VisualBaseline.Normalize(win.CaptureRenderedFrame()!);
        var (differing, total, reason) = VisualBaseline.Compare(a, b);
        Assert.Null(reason);
        Assert.True(total > 0);
        Assert.Equal(0, differing);
    }

    [AvaloniaFact]
    public void Changed_renders_are_detected()
    {
        var a = VisualBaseline.Normalize(ColorWindow(Color.FromRgb(0xFF, 0x5C, 0x35)).CaptureRenderedFrame()!);
        var b = VisualBaseline.Normalize(ColorWindow(Color.FromRgb(0x00, 0x47, 0xFF)).CaptureRenderedFrame()!);
        var (differing, _, reason) = VisualBaseline.Compare(a, b);
        Assert.Null(reason);
        Assert.True(differing > 0, "the gate failed to detect an obvious change");
    }
}
