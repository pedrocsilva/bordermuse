using System.Text.Json;
using BorderMuse.Core;
using BorderMuse.Geometry;
using Xunit;

namespace BorderMuse.Tests;

public sealed class SessionTests : IDisposable
{
    private readonly string root = Path.Combine(Path.GetTempPath(), "bordermuse-tests-" + Guid.NewGuid());
    public SessionTests() => Directory.CreateDirectory(root);
    public void Dispose() => Directory.Delete(root, true);
    private string Input(string name = "photo.png")
    {
        var path = Path.Combine(root, name);
        File.WriteAllText(path, "synthetic fixture");
        return path;
    }
    private sealed class Processor : IImageProcessor
    {
        public Action? BeforeExport;
        public ImageInfo Inspect(string path) => new(new PixelSize(100, 80), 8, 1, "png", FileVersion.Read(path));
        public byte[] Preview(string path, int edge, FileVersion? expected = null) => [];
        public void Export(string input, string output, BorderSettings settings, FileVersion expected, CancellationToken token)
        {
            BeforeExport?.Invoke();
            token.ThrowIfCancellationRequested();
            expected.Validate(input);
            File.Copy(input, output, false);
        }
    }
    [Fact]
    public async Task DeduplicatesPreservesOutputsAndRetriesChangedInput()
    {
        var processor = new Processor();
        var session = new PhotoSession(processor, new PresetStore(Path.Combine(root, "presets.json")));
        string input = Input();
        await session.ImportAsync([input, input]);
        Assert.Single(session.Photos);
        var id = session.SelectedId;
        await session.ExportAsync(root);
        string first = Assert.Single(session.Result!.Outputs);
        byte[] original = File.ReadAllBytes(first);
        await session.ExportAsync(root);
        Assert.EndsWith("-border-2.png", Assert.Single(session.Result!.Outputs));
        File.WriteAllText(input, "updated synthetic fixture");
        await session.ExportAsync(root);
        Assert.Single(session.Issues);
        Assert.Empty(session.Result!.Outputs);
        await session.ExportAsync(root, true);
        Assert.Empty(session.Issues);
        Assert.Single(session.Result!.Outputs);
        Assert.Equal(id, session.SelectedId);
        Assert.Equal(original, File.ReadAllBytes(first));
    }
    [Fact]
    public async Task CancellationPreservesFirstOutputAndImportIsQueued()
    {
        var processor = new Processor();
        var session = new PhotoSession(processor, new PresetStore(Path.Combine(root, "presets.json")));
        var a = Input();
        var b = Input("second.png");
        await session.ImportAsync([a]);
        var photo = session.Photos[0];
        using var cancel = new CancellationTokenSource();
        var result = await new BatchExporter(processor).RunAsync([photo, photo], root, new(), p => { if (p.Completed == 2) cancel.Cancel(); }, cancel.Token);
        Assert.True(result.Canceled);
        Assert.Single(result.Outputs);
        Assert.Single(Directory.GetFiles(root, "*-border*"));
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        processor.BeforeExport = () => { entered.TrySetResult(); release.Task.GetAwaiter().GetResult(); };
        var export = session.ExportAsync(root);
        await entered.Task;
        await session.ImportAsync([b]);
        Assert.Single(session.Photos);
        session.CancelExport();
        release.SetResult();
        await export;
        Assert.True(session.Result!.Canceled);
        Assert.Equal(2, session.Photos.Count);
        Assert.True(session.CanExport);
    }
    [Fact]
    public void MobileReferenceAppliesOnlyGeometryAndCannotBeDeleted()
    {
        var store = new PresetStore(Path.Combine(root, "presets.json"));
        var session = new PhotoSession(new Processor(), store) { Settings = new BorderSettings { Quality = 73, KeepMetadata = false } };
        session.UsePreset(Preset.MobileReferenceId);
        Assert.True(session.Settings.IsMobileReference);
        Assert.Equal("5:4", session.Settings.Ratio); Assert.Equal(10, session.Settings.Thickness);
        Assert.True(session.Settings.ReduceSize); Assert.Equal(2048, session.Settings.LongEdge);
        Assert.Equal(73, session.Settings.Quality); Assert.False(session.Settings.KeepMetadata);
        Assert.False(session.CanDeleteSelectedPreset);
        session.DeletePreset(); Assert.False(File.Exists(store.Path));
        session.Settings = session.Settings with { Quality = 81 }; session.NotifySettingsChanged();
        Assert.Equal(Preset.MobileReferenceId, session.SelectedPreset);
        session.SavePreset("My reference copy"); Assert.True(session.CanDeleteSelectedPreset);
        Assert.Single(store.Load());
        session.UsePreset(Preset.MobileReferenceId);
        session.Settings = session.Settings with { ReduceSize = false }; session.NotifySettingsChanged();
        Assert.Null(session.SelectedPreset);
        Assert.Single(session.Presets);
    }
    [Fact]
    public void PresetsUseTheSharedSchemaAndRejectInvalidSettings()
    {
        var store = new PresetStore(Path.Combine(root, "presets.json"));
        var session = new PhotoSession(new Processor(), store);
        session.Settings = new BorderSettings { Ratio = "4:5", Thickness = 20 };
        session.SavePreset("Portrait");
        var saved = Assert.Single(store.Load());
        Assert.Equal("4:5", saved.Settings.Ratio);
        using var json = JsonDocument.Parse(File.ReadAllText(store.Path));
        Assert.Equal(1, json.RootElement.GetProperty("version").GetInt32());
        Assert.Equal(CanvasLayout.ContractId, json.RootElement.GetProperty("geometryContract").GetString());
        session.Settings = new BorderSettings { Thickness = 51 };
        Assert.Throws<ImageException>(() => session.SavePreset("Invalid"));
        File.WriteAllText(store.Path, "{\"version\":2}");
        Assert.Empty(store.Load());
        Assert.Equal("1,100 × 880 px", Strings.Format("output", 1100, 880).Replace("Output: ", ""));
    }
}
