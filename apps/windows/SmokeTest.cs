using System.Text.Json;
using BorderMuse.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;

namespace BorderMuse.Windows;

public sealed partial class MainWindow
{
    // Opt-in integration harness. It uses the real workspace/session/codec and an
    // isolated preset store; it does not replace file-panel or assistive-tech QA.
    internal async Task SmokeAsync(string directory)
    {
        Directory.CreateDirectory(directory);
        for (int attempt = 0; root.XamlRoot is null && attempt < 100; attempt++)
            await Task.Delay(50);
        if (root.XamlRoot is null)
            throw new InvalidOperationException("Workspace did not load.");
        string input = Path.Combine(directory, "synthetic.png");
        byte[] pixels = new byte[101 * 67 * 3];
        for (int y = 0; y < 67; y++)
            for (int x = 0; x < 101; x++)
            {
                int i = (y * 101 + x) * 3;
                pixels[i] = (byte)(x < 50 ? 210 : 30);
                pixels[i + 1] = (byte)(y < 33 ? 130 : 40);
                pixels[i + 2] = 90;
            }
        var bitmap = System.Windows.Media.Imaging.BitmapSource.Create(101, 67, 96, 96, System.Windows.Media.PixelFormats.Rgb24, null, pixels, 303);
        var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
        encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
        using (var output = File.Create(input))
            encoder.Save(output);
        byte[] original = File.ReadAllBytes(input);
        root.RequestedTheme = ElementTheme.Light;
        await session.ImportAsync([input, input]);
        if (session.Photos.Count != 1)
            throw new InvalidOperationException("Import deduplication failed.");
        thickness.Text = "7";
        ratios.SelectedItem = ratios.Items.Cast<RatioChoice>().First(r => r.Value == "5:4");
        Refresh();
        for (int attempt = 0; photoImage.Source is null && attempt < 100; attempt++)
            await Task.Delay(50);
        if (photoImage.Source is null || session.Layout is not { Width: 107, Height: 85 })
            throw new InvalidOperationException("Preview is not ready or has incorrect geometry.");
        await Capture(Path.Combine(directory, "light-workspace.png"));
        session.SavePreset("Synthetic QA");
        var id = session.SelectedPreset;
        session.Settings = new BorderSettings();
        session.UsePreset(id);
        SyncSettings();
        if (session.Settings.Thickness != 7 || session.Settings.Ratio != "5:4")
            throw new InvalidOperationException("Preset did not restore settings.");
        string exports = Path.Combine(directory, "outputs");
        Directory.CreateDirectory(exports);
        await session.ExportAsync(exports);
        string first = session.Result!.Outputs.Single();
        byte[] firstBytes = File.ReadAllBytes(first);
        await session.ExportAsync(exports);
        if (!File.Exists(Path.Combine(exports, "synthetic-border-2.png")) || !File.ReadAllBytes(first).SequenceEqual(firstBytes) || !File.ReadAllBytes(input).SequenceEqual(original))
            throw new InvalidOperationException("Export overwrite/original protection failed.");
        var sourceSize = session.Photos[0].Info.Size;
        photoSize.SelectedItem = photoSize.Items.Cast<SizeChoice>().First(c => c.LongEdge == 2048);
        await Task.Delay(50);
        if (!session.Settings.ReduceSize || session.Settings.LongEdge != 2048 || session.Settings.PreparedSize(sourceSize) != sourceSize)
            throw new InvalidOperationException("The 2048 preset must retain smaller photos without enlargement.");
        photoSize.SelectedItem = photoSize.Items.Cast<SizeChoice>().First(c => c.LongEdge == -1);
        longEdge.Text = "51";
        await Task.Delay(50);
        if (session.Settings.PreparedSize(sourceSize) != new BorderMuse.Geometry.PixelSize(51, 34))
            throw new InvalidOperationException("Custom photo resizing did not prepare the expected dimensions.");
        session.SavePreset("Resized QA");
        var resizedPreset = session.SelectedPreset;
        longEdge.Text = "abc";
        await Task.Delay(50);
        if (session.CanExport) throw new InvalidOperationException("Invalid custom size did not block export.");
        photoSize.SelectedItem = photoSize.Items.Cast<SizeChoice>().First(c => c.LongEdge == 0);
        await Task.Delay(50);
        if (!session.CanExport || session.Settings.ReduceSize) throw new InvalidOperationException("Original size did not clear the hidden invalid draft.");
        session.UsePreset(resizedPreset);
        SyncSettings();
        if (photoSize.SelectedItem is not SizeChoice { LongEdge: -1 } || session.Settings.LongEdge != 51)
            throw new InvalidOperationException("Existing resize settings did not restore the Custom choice.");
        session.UsePreset(id);
        SyncSettings();
        options.IsExpanded = true;
        await Task.Delay(300);
        await Capture(Path.Combine(directory, "light-expanded-options.png"));
        var optionBounds = options.TransformToVisual(inspectorScroll).TransformBounds(new global::Windows.Foundation.Rect(0, 0, options.ActualWidth, options.ActualHeight));
        if (optionBounds.Bottom > inspectorScroll.ViewportHeight + 1)
            throw new InvalidOperationException($"Expanded export settings end at {optionBounds.Bottom}, beyond viewport {inspectorScroll.ViewportHeight}.");
        root.RequestedTheme = ElementTheme.Dark;
        AppWindow.Resize(new global::Windows.Graphics.SizeInt32(980, 680));
        options.IsExpanded = true;
        thickness.Text = "abc";
        for (int attempt = 0; session.InputsValid && attempt < 100; attempt++)
            await Task.Delay(25);
        Refresh();
        if (session.CanExport || export.IsEnabled || validation.Visibility != Visibility.Visible)
            throw new InvalidOperationException("Invalid draft did not block export.");
        await Capture(Path.Combine(directory, "dark-minimum-validation.png"));
        var errorBounds = validation.TransformToVisual(root).TransformBounds(new global::Windows.Foundation.Rect(0, 0, validation.ActualWidth, validation.ActualHeight));
        if (errorBounds.Top < 0 || errorBounds.Bottom > root.ActualHeight || validation.ActualHeight < 10)
            throw new InvalidOperationException("Validation explanation is outside the workspace.");
        root.RequestedTheme = ElementTheme.Light;
        await Capture(Path.Combine(directory, "light-minimum-validation.png"));
        root.RequestedTheme = ElementTheme.Dark;
        thickness.Text = "7";
        for (int attempt = 0; !session.InputsValid && attempt < 100; attempt++)
            await Task.Delay(25);
        inspectorScroll.ChangeView(null, double.MaxValue, null, true);
        await Task.Delay(250);
        await Capture(Path.Combine(directory, "dark-minimum-options.png"));
        string activated = Path.Combine(directory, "activated photo.png");
        File.Copy(input, activated);
        var start = new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false };
        start.ArgumentList.Add(activated);
        using (var secondary = System.Diagnostics.Process.Start(start)!)
        {
            await secondary.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(20));
            if (secondary.ExitCode != 0)
                throw new InvalidOperationException("Secondary instance did not redirect activation.");
        }
        for (int attempt = 0; session.Photos.Count < 2 && attempt < 100; attempt++)
            await Task.Delay(50);
        if (session.Photos.Count != 2 || !session.Photos.Any(p => p.Path == activated))
            throw new InvalidOperationException("An ordinary second launch did not import its photo into the existing window.");
        File.WriteAllText(Path.Combine(directory, "report.json"), JsonSerializer.Serialize(new
        {
            passed = true,
            photos = session.Photos.Count,
            canvas = new[] { 107, 85 },
            originalPreserved = true,
            existingOutputPreserved = true,
            presetRestored = true,
            invalidDraftBlocked = true,
            redirectedFileImported = true,
            resizeChoicesValidated = true
        }));
        allowClose = true;
        Close();
    }
    private async Task Capture(string path)
    {
        root.UpdateLayout();
        await Task.Delay(250);
        var render = new RenderTargetBitmap();
        await render.RenderAsync(root);
        if (render.PixelWidth < 100 || render.PixelHeight < 100)
            throw new InvalidOperationException("Invalid UI capture size.");
        var buffer = await render.GetPixelsAsync();
        byte[] data = new byte[buffer.Length];
        using (var reader = DataReader.FromBuffer(buffer))
            reader.ReadBytes(data);
        if (!data.Any(b => b != 0))
            throw new InvalidOperationException("UI capture is blank.");
        using var stream = new InMemoryRandomAccessStream();
        var encoder = await global::Windows.Graphics.Imaging.BitmapEncoder.CreateAsync(global::Windows.Graphics.Imaging.BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(global::Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8, global::Windows.Graphics.Imaging.BitmapAlphaMode.Premultiplied, (uint)render.PixelWidth, (uint)render.PixelHeight, 96, 96, data);
        await encoder.FlushAsync();
        using var input = stream.GetInputStreamAt(0);
        using var outputReader = new DataReader(input);
        await outputReader.LoadAsync((uint)stream.Size);
        byte[] encoded = new byte[stream.Size];
        outputReader.ReadBytes(encoded);
        File.WriteAllBytes(path, encoded);
    }
}
