using System.Collections.Generic;

namespace AppName.App.ViewModels;

/// One shell section (a NavigationView destination). The scaffold renders these as
/// placeholder cards; replace each with a real view + view model as features land.
public sealed class SectionViewModel : ViewModelBase
{
    public SectionViewModel(string title, string blurb, IReadOnlyList<string> items)
    {
        Title = title;
        Blurb = blurb;
        Items = items;
    }

    public string Title { get; }
    public string Blurb { get; }
    public IReadOnlyList<string> Items { get; }
}
