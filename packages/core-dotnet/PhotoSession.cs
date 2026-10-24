using BorderMuse.Geometry;

namespace BorderMuse.Core;

/// <summary>Application state independent of Windows controls and image codecs.</summary>
public sealed class PhotoSession(IImageProcessor processor, PresetStore store)
{
    public event Action? Changed;
    public List<Photo> Photos { get; } = [];
    public List<PhotoIssue> Issues { get; } = [];
    public IReadOnlyList<Preset> Presets { get; private set; } = store.Load();
    public BorderSettings Settings { get; set; } = new();
    public Guid? SelectedId
    {
        get; private set;
    }
    public Guid? SelectedPreset
    {
        get; private set;
    }
    public Photo? Selected => Photos.FirstOrDefault(p => p.Id == SelectedId) ?? Photos.FirstOrDefault();
    public bool IsImporting
    {
        get; private set;
    }
    public bool IsExporting
    {
        get; private set;
    }
    public bool InputsValid { get; set; } = true;
    public BatchProgress Progress { get; private set; } = new(0, 0);
    public ExportResult? Result
    {
        get; private set;
    }
    private readonly Queue<string> pending = new();
    private readonly SemaphoreSlim importGate = new(1);
    private CancellationTokenSource? exportCancellation;
    private Task? exportTask;
    public CanvasLayout? Layout
    {
        get
        {
            try
            {
                return Selected is { } photo ? Settings.Layout(photo.Info.Size) : null;
            }
            catch { return null; }
        }
    }
    public bool CanExport => Photos.Count > 0 && !IsImporting && !IsExporting && InputsValid && Layout is not null;
    public void NotifySettingsChanged()
    {
        SelectedPreset = null;
        Result = null;
        Changed?.Invoke();
    }
    public void Select(Guid id)
    {
        if (Photos.Any(p => p.Id == id))
        {
            SelectedId = id;
            Changed?.Invoke();
        }
    }
    public void SelectNeighbor(int delta)
    {
        if (Photos.Count == 0)
            return;
        int index = Math.Max(0, Photos.FindIndex(p => p.Id == SelectedId));
        Select(Photos[Math.Clamp(index + delta, 0, Photos.Count - 1)].Id);
    }
    public void Remove(Guid id)
    {
        if (IsImporting || IsExporting)
            return;
        Photos.RemoveAll(p => p.Id == id);
        if (SelectedId == id)
            SelectedId = Photos.FirstOrDefault()?.Id;
        Changed?.Invoke();
    }
    public void Clear()
    {
        if (IsImporting || IsExporting)
            return;
        Photos.Clear();
        Issues.Clear();
        SelectedId = null;
        Result = null;
        Changed?.Invoke();
    }
    private static string Canonical(string path)
    {
        var file = new FileInfo(Path.GetFullPath(path));
        return file.ResolveLinkTarget(true)?.FullName ?? file.FullName;
    }
    public async Task ImportAsync(IEnumerable<string> paths)
    {
        lock (pending)
        foreach (var path in paths)
            pending.Enqueue(path);
        if (IsExporting)
            return;
        await importGate.WaitAsync();
        try
        {
            IsImporting = true;
            Changed?.Invoke();
            while (true)
            {
                string path;
                lock (pending)
                {
                    if (pending.Count == 0)
                        break;
                    path = pending.Dequeue();
                }
                try
                {
                    string canonical = Canonical(path);
                    var info = await Task.Run(() => processor.Inspect(canonical));
                    int index = Photos.FindIndex(p => string.Equals(p.Path, canonical, StringComparison.OrdinalIgnoreCase));
                    if (index >= 0)
                    {
                        if (Photos[index].Info.Version != info.Version)
                        {
                            Photos[index] = Photos[index] with
                            {
                                Info = info
                            };
                            Result = null;
                        }
                    }
                    else
                    {
                        var photo = new Photo(Guid.NewGuid(), canonical, info);
                        Photos.Add(photo);
                        SelectedId ??= photo.Id;
                    }
                }
                catch (Exception error) { Issues.Add(new PhotoIssue(path, error is ImageException ? error.Message : Strings.Text("importError"), false)); }
                Changed?.Invoke();
            }
        }
        finally { IsImporting = false; importGate.Release(); Changed?.Invoke(); }
    }
    public Task ExportAsync(string folder, bool retry = false)
    {
        if (!CanExport)
            return Task.CompletedTask;
        var failed = Issues.Where(i => i.CanRetry).Select(i => i.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var snapshot = Photos.Where(p => !retry || failed.Contains(p.Path)).ToArray();
        if (snapshot.Length == 0)
            return Task.CompletedTask;
        IsExporting = true;
        Result = null;
        Progress = new(0, snapshot.Length);
        Issues.RemoveAll(i => i.CanRetry);
        exportCancellation = new CancellationTokenSource();
        exportTask = RunExportAsync(snapshot, folder, Settings with
        {
        }, retry, exportCancellation.Token);
        Changed?.Invoke();
        return exportTask;
    }
    private async Task RunExportAsync(Photo[] snapshot, string folder, BorderSettings settings, bool refresh, CancellationToken token)
    {
        try
        {
            if (refresh)
            {
                for (int index = 0; index < snapshot.Length && !token.IsCancellationRequested; index++)
                {
                    try
                    {
                        var info = await Task.Run(() => processor.Inspect(snapshot[index].Path));
                        snapshot[index] = snapshot[index] with
                        {
                            Info = info
                        };
                        int existing = Photos.FindIndex(p => p.Id == snapshot[index].Id);
                        if (existing >= 0)
                            Photos[existing] = snapshot[index];
                    }
                    catch { /* Keep unreadable inputs so the worker reports the per-file error. */ }
                }
            }
            Result = await new BatchExporter(processor).RunAsync(snapshot, folder, settings,
                progress => { Progress = progress; Changed?.Invoke(); }, token);
            Issues.AddRange(Result.Issues);
        }
        finally
        {
            IsExporting = false;
            exportCancellation?.Dispose();
            exportCancellation = null;
            Changed?.Invoke();
            if (pending.Count > 0)
                await ImportAsync([]);
        }
    }
    public void CancelExport() => exportCancellation?.Cancel();
    public async Task CancelExportAndWaitAsync()
    {
        var task = exportTask;
        CancelExport();
        if (task is not null)
            await task;
    }
    public void UsePreset(Guid? id)
    {
        var preset = Presets.FirstOrDefault(p => p.Id == id);
        if (preset is not null)
        {
            Settings = preset.Settings with
            {
            };
            InputsValid = true;
            Result = null;
        }
        SelectedPreset = id;
        Changed?.Invoke();
    }
    public void SavePreset(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || !InputsValid)
            return;
        Settings.Validate();
        var preset = new Preset(Guid.NewGuid(), name.Trim(), Settings with
        {
        });
        var updated = Presets.Append(preset).ToArray();
        store.Save(updated);
        Presets = updated;
        SelectedPreset = preset.Id;
        Changed?.Invoke();
    }
    public void DeletePreset()
    {
        var updated = Presets.Where(p => p.Id != SelectedPreset).ToArray();
        store.Save(updated);
        Presets = updated;
        SelectedPreset = null;
        Changed?.Invoke();
    }
}
