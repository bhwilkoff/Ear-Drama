using System;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.Input;
using FluentAvalonia.UI.Controls;
using AppName.App.ViewModels;

namespace AppName.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();

        Loaded += (_, _) =>
        {
            if (Nav.SelectedItem is null && Nav.MenuItems.Count > 0)
                Nav.SelectedItem = Nav.MenuItems[0];
            // Render the landing surface DIRECTLY rather than waiting for
            // SelectionChanged. FANavigationView can settle on the first item on its
            // own without ever raising the event, which leaves the detail pane blank
            // until the user clicks the sidebar.
            if (ContentHost.Content is null)
                Navigate((Nav.SelectedItem as FANavigationViewItem)?.Tag as string ?? "home");
            // Deep-link inbox: parse Program.LaunchUrl here and Select() the target —
            // external entry points never mutate navigation directly. Test doors
            // (LaunchHooks, DEBUG only) are consumed in the same place.
            OpenDoors();
        };

        // App-level accelerators — the Windows twin of the macOS menu commands.
        // Windows users reach for these; without them the app is pointer-only for its
        // most common verbs.
        KeyBindings.Add(new KeyBinding
        {
            Gesture = new KeyGesture(Key.OemComma, KeyModifiers.Control),
            Command = new RelayCommand(() => Navigate("settings")),
        });
    }

    private void OpenDoors()
    {
        if (LaunchHooks.StartTab is { } tab)
            Select(tab);
        if (LaunchHooks.StartItem is { } item)
            ContentHost.Content = new TextBlock { Text = $"Item: {item}" };  // FILL IN: open the item's detail view
        // End the door's activity on the app's own clock (stop playback, leave the
        // room) so a crashed harness cannot leave it running.
        if (LaunchHooks.DoorSeconds is { } seconds)
            DispatcherTimer.RunOnce(() => Select("home"), TimeSpan.FromSeconds(seconds));
    }

    /// Select a nav item by tag (keeps the sidebar highlight and the content in step).
    private void Select(string tag)
    {
        foreach (var item in Nav.MenuItems.OfType<FANavigationViewItem>())
            if (item.Tag as string == tag) { Nav.SelectedItem = item; return; }
        Navigate(tag);
    }

    private void OnNavSelectionChanged(object? sender, FANavigationViewSelectionChangedEventArgs e)
    {
        string tag = e.IsSettingsSelected
            ? "settings"
            : (e.SelectedItem as FANavigationViewItem)?.Tag as string ?? "home";
        Navigate(tag);
    }

    /// Swap the detail pane. Replace the SectionView fallback with real views as
    /// features land (see the Navigate() in a shipped app for the pattern).
    private void Navigate(string tag)
    {
        if (DataContext is MainWindowViewModel vm && vm.Sections.TryGetValue(tag, out var section))
            ContentHost.Content = new SectionView { DataContext = section };
    }
}
