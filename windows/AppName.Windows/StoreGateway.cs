using Windows.ApplicationModel;

namespace AppName.Windows;

/// The WinRT edge — the only code in the solution allowed to touch
/// Windows.Services.Store / Windows.ApplicationModel. The app finds this class BY
/// NAME via Assembly.LoadFrom + reflection (it cannot reference this project — see
/// the csproj), so treat the type and member names as a contract: pin them with a
/// test on the app side, and never rename casually.
///
/// When adding Store in-app purchases here, the expensive lessons:
/// - Use StoreContext.GetAssociatedStoreProductsAsync (the app's own add-ons), NOT
///   GetStoreProductsAsync — the latter's kind filter silently returns nothing for
///   subscription add-ons, with no error anywhere.
/// - A subscription is a "Durable" add-on carrying StoreSku.SubscriptionInfo;
///   "Subscription" is not a product kind. One query covers lifetime and plans.
/// - StoreContext needs an owner HWND before it shows purchase UI on desktop —
///   marshal it in from the app (Win32HostInterop.MainWindowHandle), don't reach for
///   Avalonia from here.
/// - No API can list Store add-ons once one is a subscription: verify product ids by
///   eye in Partner Center, and gate ships with a workflow that reads them back
///   (windows-store-addons.yml).
public static class StoreGateway
{
    /// True when running from an installed MSIX package (Store or sideload).
    /// Package.Current throws for a bare .exe, which is how a loose dev build
    /// reports false.
    public static bool IsPackaged
    {
        get
        {
            try { return Package.Current is not null; }
            catch { return false; }
        }
    }

    /// The installed package's family name, or null for a bare .exe. The value the
    /// https deep-link association (.well-known/windows-app-web-link) must carry.
    public static string? PackageFamilyName
    {
        get
        {
            try { return Package.Current.Id.FamilyName; }
            catch { return null; }
        }
    }
}
