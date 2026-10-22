using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Avalonia.Controls;

namespace AppName.App.Services;

/// The ONE Win32 seam — the `#if os()` analog. Everything that needs the HWND lives
/// here: taskbar progress and global hotkeys. AppName.Core NEVER references this, so
/// Core keeps compiling for the headless test host and the macOS dev head.
///
/// Every entry point no-ops off Windows rather than throwing, so the same app code
/// runs on the Mac head and in headless tests. That is what makes it testable at
/// all: keep the STATE decisions pure functions (unit-tested anywhere); only the
/// final P/Invoke is Windows-gated.
///
/// Snap Layouts need no code: they come free with the standard maximize button, and
/// MainWindow uses standard decorations (no ExtendClientArea). If custom chrome ever
/// lands, the WM_NCHITTEST -> HTMAXBUTTON fix belongs here.
public static class Win32HostInterop
{
    public enum TaskbarProgress
    {
        None,
        Indeterminate,
        Normal,
        Error,
        Paused,
    }

    /// Example of the pure-function half: what the taskbar should show for an
    /// N-of-M task. The mapping is the product behaviour and is testable off
    /// Windows; the P/Invoke below is just how it gets painted.
    public static (TaskbarProgress State, ulong Value, ulong Max) StepIndicator(int done, int total)
    {
        if (total <= 0) return (TaskbarProgress.None, 0, 0);
        var clamped = (ulong)Math.Clamp(done, 0, total);
        return clamped >= (ulong)total
            ? (TaskbarProgress.Paused, (ulong)total, (ulong)total)
            : (TaskbarProgress.Normal, clamped, (ulong)total);
    }

    public static bool IsSupported => OperatingSystem.IsWindows();

    private static IntPtr Hwnd(Window window) =>
        window.TryGetPlatformHandle()?.Handle ?? IntPtr.Zero;

    /// The main window's HWND, or IntPtr.Zero when there isn't one yet (headless
    /// tests, or before the shell opens). StoreContext needs an owner handle before
    /// it will show Store purchase UI on desktop — keep that lookup here, in the one
    /// Win32 seam, rather than teaching a store gateway about Avalonia's lifetime.
    public static IntPtr MainWindowHandle()
    {
        if (!OperatingSystem.IsWindows()) return IntPtr.Zero;
        var lifetime = Avalonia.Application.Current?.ApplicationLifetime
            as Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime;
        var window = lifetime?.MainWindow;
        return window is null ? IntPtr.Zero : Hwnd(window);
    }

    /// Paint the taskbar button. No-op off Windows / before the handle exists.
    public static void SetTaskbarProgress(Window window, TaskbarProgress state, ulong value, ulong max)
    {
        if (!OperatingSystem.IsWindows()) return;
        var hwnd = Hwnd(window);
        if (hwnd == IntPtr.Zero) return;
        SetTaskbarProgressWindows(hwnd, state, value, max);
    }

    [SupportedOSPlatform("windows")]
    private static void SetTaskbarProgressWindows(IntPtr hwnd, TaskbarProgress state, ulong value, ulong max)
    {
        try
        {
            var list = TaskbarList;
            if (list is null) return;
            list.SetProgressState(hwnd, state switch
            {
                TaskbarProgress.Indeterminate => TbpFlag.Indeterminate,
                TaskbarProgress.Normal => TbpFlag.Normal,
                TaskbarProgress.Error => TbpFlag.Error,
                TaskbarProgress.Paused => TbpFlag.Paused,
                _ => TbpFlag.NoProgress,
            });
            if (state is TaskbarProgress.Normal or TaskbarProgress.Error or TaskbarProgress.Paused && max > 0)
                list.SetProgressValue(hwnd, value, max);
        }
        catch (COMException)
        {
            // The shell can refuse (e.g. no taskbar in a session). Losing the taskbar
            // hint must never take the app down.
        }
    }

    [SupportedOSPlatform("windows")]
    private static ITaskbarList3? _taskbarList;
    [SupportedOSPlatform("windows")]
    private static bool _taskbarInitFailed;

    [SupportedOSPlatform("windows")]
    private static ITaskbarList3? TaskbarList
    {
        get
        {
            if (_taskbarList is not null || _taskbarInitFailed) return _taskbarList;
            try
            {
                var t = Type.GetTypeFromCLSID(new Guid("56FDF344-FD6D-11d0-958A-006097C9A090"));
                if (t is null) { _taskbarInitFailed = true; return null; }
                _taskbarList = (ITaskbarList3?)Activator.CreateInstance(t);
                _taskbarList?.HrInit();
            }
            catch (Exception e) when (e is COMException or InvalidCastException or NotSupportedException)
            {
                _taskbarInitFailed = true;
                _taskbarList = null;
            }
            return _taskbarList;
        }
    }

    private enum TbpFlag
    {
        NoProgress = 0,
        Indeterminate = 0x1,
        Normal = 0x2,
        Error = 0x4,
        Paused = 0x8,
    }

    [ComImport]
    [Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eefaf")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ITaskbarList3
    {
        // ITaskbarList
        void HrInit();
        void AddTab(IntPtr hwnd);
        void DeleteTab(IntPtr hwnd);
        void ActivateTab(IntPtr hwnd);
        void SetActiveAlt(IntPtr hwnd);
        // ITaskbarList2
        void MarkFullscreenWindow(IntPtr hwnd, [MarshalAs(UnmanagedType.Bool)] bool fFullscreen);
        // ITaskbarList3 — only the two we use are declared faithfully; the rest must
        // still occupy their vtable slots in order or the calls land on the wrong
        // method.
        void SetProgressValue(IntPtr hwnd, ulong ullCompleted, ulong ullTotal);
        void SetProgressState(IntPtr hwnd, TbpFlag tbpFlags);
    }

    // ---- Global hotkeys (fire even when another app has focus) ----

    public const uint ModAlt = 0x0001;
    public const uint ModControl = 0x0002;
    public const uint ModShift = 0x0004;
    public const uint ModNoRepeat = 0x4000;

    [DllImport("user32.dll", SetLastError = true)]
    [SupportedOSPlatform("windows")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    [SupportedOSPlatform("windows")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private static readonly HashSet<int> Registered = new();

    /// Register a system-wide hotkey against the window. Returns false off Windows,
    /// or when another app already owns the combination — the caller must treat a
    /// false as "the hotkey is unavailable", never as a fatal error.
    public static bool TryRegisterHotKey(Window window, int id, uint modifiers, uint virtualKey)
    {
        if (!OperatingSystem.IsWindows()) return false;
        var hwnd = Hwnd(window);
        if (hwnd == IntPtr.Zero) return false;
        if (!RegisterHotKey(hwnd, id, modifiers | ModNoRepeat, virtualKey)) return false;
        Registered.Add(id);
        return true;
    }

    public static void UnregisterHotKeys(Window window)
    {
        if (!OperatingSystem.IsWindows()) return;
        var hwnd = Hwnd(window);
        if (hwnd == IntPtr.Zero) return;
        foreach (var id in Registered) UnregisterHotKey(hwnd, id);
        Registered.Clear();
    }
}
