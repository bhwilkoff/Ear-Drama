using System;

namespace AppName.App;

/// Test "doors": env vars that open a surface directly, so a harness
/// (tools/win_run.py) can reach any screen without clicking blind. Names match
/// tools/app_config.py (HOOK_START_TAB, HOOK_START_ITEM, HOOK_MUTE,
/// HOOK_DOOR_SECONDS). DEBUG builds only — every accessor is null/false in
/// Release, so the doors are no-ops in the shipped app.
public static class LaunchHooks
{
    public static string? StartTab => Env("APP_START_TAB");
    public static string? StartItem => Env("APP_START_ITEM");
    public static bool Mute => Env("APP_MUTE") == "1";
    public static int? DoorSeconds => int.TryParse(Env("APP_DOOR_SECONDS"), out var s) ? s : null;

    private static string? Env(string name)
    {
#if DEBUG
        var value = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrWhiteSpace(value) ? null : value;
#else
        return null;
#endif
    }
}
