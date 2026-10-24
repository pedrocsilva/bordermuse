using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Windows.ApplicationModel.Activation;
using Windows.Storage;

namespace BorderMuse.Windows;

public sealed partial class App : Application
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
        InitializeComponent();
    }
    protected override async void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
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
            if (activation.Data is IFileActivatedEventArgs files)
                await window.ImportAsync(files.Files.OfType<StorageFile>().Select(f => f.Path));
            else if (activation.Data is ICommandLineActivatedEventArgs command)
                await window.ImportAsync(Shell.Arguments(command.Operation.Arguments).Skip(1));
            else if (activation.Data is ILaunchActivatedEventArgs launch)
                await window.ImportAsync(Shell.Arguments(launch.Arguments).Skip(1).Where(File.Exists));
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
