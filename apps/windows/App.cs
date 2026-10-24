using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Windows.AppLifecycle;
using Windows.ApplicationModel.Activation;
using Windows.Storage;

namespace BorderMuse.Windows;

internal static class Program
{
    [STAThread]
    public static void Main()
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(parameters =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            try { _ = new App(); }
            catch (Exception error) { App.RecordSmokeFailure(error.ToString()); throw; }
        });
    }
}

public sealed class App : Application
{
    private MainWindow? window;
    private AppInstance? instance;
    internal static void RecordSmokeFailure(string message)
    {
        if (Environment.GetEnvironmentVariable("BORDERMUSE_SMOKE_DIR") is not { } directory)
            return;
        Directory.CreateDirectory(directory);
        File.AppendAllText(Path.Combine(directory, "failure.txt"), message + Environment.NewLine);
    }
    public App()
    {
        UnhandledException += (_, error) => RecordSmokeFailure(error.Message + Environment.NewLine + error.Exception);
    }
    protected override async void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        Resources = new ResourceDictionary();
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        instance = AppInstance.FindOrRegisterForKey("BorderMuse.Windows");
        if (!instance.IsCurrent)
        {
            await instance.RedirectActivationToAsync(AppInstance.GetCurrent().GetActivatedEventArgs());
            Environment.Exit(0);
            return;
        }
        window = new MainWindow();
        instance.Activated += (_, activation) => window.DispatcherQueue.TryEnqueue(async () =>
        {
            window.Activate();
            if (activation.Data is FileActivatedEventArgs files)
                await window.ImportAsync(files.Files.OfType<StorageFile>().Select(f => f.Path));
            else if (activation.Data is CommandLineActivatedEventArgs command)
                await window.ImportAsync(Shell.Arguments(command.Operation.Arguments).Skip(1));
        });
        window.Activate();
        await window.ImportAsync(Environment.GetCommandLineArgs().Skip(1).Where(File.Exists));
        if (Environment.GetEnvironmentVariable("BORDERMUSE_SMOKE_DIR") is { } smoke)
        {
            try
            {
                await window.SmokeAsync(smoke);
            }
            catch (Exception error)
            {
                Directory.CreateDirectory(smoke);
                File.WriteAllText(Path.Combine(smoke, "failure.txt"), error.ToString());
                Environment.Exit(1);
            }
        }
    }
}
