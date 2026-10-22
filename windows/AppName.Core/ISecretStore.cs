namespace AppName.Core;

/// The credential-storage seam — the Windows analog of the Apple Keychain rule.
/// Core only knows this interface; the app injects DpapiSecretStore on Windows and
/// FileSecretStore elsewhere (the macOS dev head, headless tests). Long-lived tokens
/// (a refresh token is enough to assume the user's identity) must NEVER sit on disk
/// in cleartext — that was a real shipped bug this seam exists to prevent.
public interface ISecretStore
{
    string? Get(string key);
    void Set(string key, string value);
    void Delete(string key);
}

/// Cleartext fallback for non-Windows hosts only. Never the Windows implementation.
public sealed class FileSecretStore : ISecretStore
{
    private readonly string _dir;

    public FileSecretStore(string dir) => _dir = dir;

    private string PathFor(string key) => Path.Combine(_dir, key + ".txt");

    public string? Get(string key)
    {
        try
        {
            var p = PathFor(key);
            return File.Exists(p) ? File.ReadAllText(p) : null;
        }
        catch { return null; }
    }

    public void Set(string key, string value)
    {
        try
        {
            Directory.CreateDirectory(_dir);
            File.WriteAllText(PathFor(key), value);
        }
        catch { }
    }

    public void Delete(string key)
    {
        try
        {
            var p = PathFor(key);
            if (File.Exists(p)) File.Delete(p);
        }
        catch { }
    }
}
