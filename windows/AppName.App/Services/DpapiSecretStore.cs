using System;
using System.IO;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using AppName.Core;

namespace AppName.App.Services;

/// The Windows twin of the Apple Keychain store. Rides the ISecretStore seam, so
/// AppName.Core stays OS-agnostic — Core only knows the interface, and this
/// Windows-only implementation is injected by the app.
///
/// Why this matters: a plain file store writes long-lived tokens (a refresh token is
/// enough to assume the user's identity) to disk in cleartext. DPAPI with
/// CurrentUser scope binds the ciphertext to the Windows user account — another user
/// on the same box cannot read it, and it is useless if copied to another machine.
///
/// DPAPI is Windows-only: off Windows this falls back to the plain file store so the
/// macOS dev head and headless tests keep working.
public sealed class DpapiSecretStore : ISecretStore
{
    private readonly string _dir;
    private readonly ISecretStore? _fallback;

    /// Extra entropy — DPAPI mixes this in, so another app running as the same user
    /// cannot decrypt these blobs just by calling Unprotect on the file.
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("AppName.secrets.v1");

    public DpapiSecretStore(string? dir = null)
    {
        _dir = dir ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AppName", "secrets");
        _fallback = OperatingSystem.IsWindows() ? null : new FileSecretStore(_dir);
    }

    private string PathFor(string key) => Path.Combine(_dir, key + ".dpapi");

    public string? Get(string key)
    {
        if (_fallback is { } f) return f.Get(key);
        return OperatingSystem.IsWindows() ? GetWindows(key) : null;
    }

    public void Set(string key, string value)
    {
        if (_fallback is { } f) { f.Set(key, value); return; }
        if (OperatingSystem.IsWindows()) SetWindows(key, value);
    }

    [SupportedOSPlatform("windows")]
    private string? GetWindows(string key)
    {
        try
        {
            var p = PathFor(key);
            if (!File.Exists(p)) return null;
            var plain = ProtectedData.Unprotect(File.ReadAllBytes(p), Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plain);
        }
        catch (CryptographicException)
        {
            // Ciphertext from another user/machine (roamed profile, restored backup)
            // is undecryptable. Drop it and re-authenticate rather than wedging
            // sign-in.
            Delete(key);
            return null;
        }
        catch { return null; }
    }

    [SupportedOSPlatform("windows")]
    private void SetWindows(string key, string value)
    {
        try
        {
            Directory.CreateDirectory(_dir);
            var blob = ProtectedData.Protect(
                Encoding.UTF8.GetBytes(value), Entropy, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(PathFor(key), blob);
        }
        catch { }
    }

    public void Delete(string key)
    {
        if (_fallback is { } f) { f.Delete(key); return; }
        try { var p = PathFor(key); if (File.Exists(p)) File.Delete(p); } catch { }
    }
}
