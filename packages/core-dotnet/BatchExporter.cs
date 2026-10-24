namespace BorderMuse.Core;

public sealed class BatchExporter(IImageProcessor processor)
{
    public Task<ExportResult> RunAsync(IReadOnlyList<Photo> photos, string folder, BorderSettings settings,
        Action<BatchProgress>? progress = null, CancellationToken cancellationToken = default) => Task.Run(() =>
    {
        settings.Validate();
        var outputs = new List<string>();
        var issues = new List<PhotoIssue>();
        bool canceled = false;
        for (int index = 0; index < photos.Count; index++)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                canceled = true;
                break;
            }
            progress?.Invoke(new BatchProgress(index + 1, photos.Count));
            var photo = photos[index];
            try
            {
                int number = 1;
                while (true)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var suffix = number == 1 ? "-border" : "-border-" + number;
                    var output = Path.Combine(folder, Path.GetFileNameWithoutExtension(photo.Path) + suffix + Path.GetExtension(photo.Path));
                    if (File.Exists(output))
                    {
                        number++;
                        continue;
                    }
                    try
                    {
                        processor.Export(photo.Path, output, settings, photo.Info.Version, cancellationToken);
                        outputs.Add(output);
                        break;
                    }
                    catch (IOException) when (File.Exists(output)) { number++; }
                }
            }
            catch (OperationCanceledException) { canceled = true; break; }
            catch (Exception error) { issues.Add(new PhotoIssue(photo.Path, Strings.Message(error), true)); }
        }
        return new ExportResult(outputs, issues, canceled);
    }, CancellationToken.None);
}
