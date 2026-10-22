using CommunityToolkit.Mvvm.ComponentModel;

namespace AppName.App.ViewModels;

/// MVVM via CommunityToolkit.Mvvm: [ObservableProperty] / [RelayCommand] on
/// partial classes. Views are parameterless and bind DataContext — a constructor
/// parameter on a View trips AVLN3001.
public class ViewModelBase : ObservableObject
{
}
