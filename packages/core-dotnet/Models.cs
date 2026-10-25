using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using BorderMuse.Geometry;

namespace BorderMuse.Core;

public sealed record BorderSettings
{
    public string Ratio { get; init; } = "original";
    public int Thickness { get; init; } = 10;
    public bool ReduceSize
    {
        get; init;
    }
    public int LongEdge { get; init; } = 3000;
    public int Quality { get; init; } = 95;
    public bool KeepMetadata { get; init; } = true;
    [JsonIgnore] public bool IsMobileReference => Ratio == "5:4" && Thickness == 10 && ReduceSize && LongEdge == 2048;
    public BorderSettings ApplyingMobileReference() => this with { Ratio = "5:4", Thickness = 10, ReduceSize = true, LongEdge = 2048 };
    public void Validate()
    {
        if (Thickness is < 0 or > 50)
            throw new ImageException("thicknessError");
        if (Quality is < 1 or > 100)
            throw new ImageException("qualityError");
        if (ReduceSize && LongEdge is < 1 or > 100_000)
            throw new ImageException("longEdgeError");
        try
        {
            _ = AspectRatio.Parse(Ratio);
        }
        catch (Exception e) when (e is FormatException or ArgumentException) { throw new ImageException("ratioError", e); }
    }
    public PixelSize PreparedSize(PixelSize source)
    {
        Validate();
        if (!ReduceSize || LongEdge >= Math.Max(source.Width, source.Height))
            return source;
        double scale = (double)LongEdge / Math.Max(source.Width, source.Height);
        return new PixelSize(Math.Max(1, checked((long)Math.Round(source.Width * scale, MidpointRounding.AwayFromZero))),
            Math.Max(1, checked((long)Math.Round(source.Height * scale, MidpointRounding.AwayFromZero))));
    }
    public CanvasLayout Layout(PixelSize source) => CanvasLayout.Calculate(PreparedSize(source), Thickness, AspectRatio.Parse(Ratio));
}

public sealed record FileVersion(long Length, long ModifiedTicks, string Sha256)
{
    public static FileVersion Read(string path)
    {
        var before = new FileInfo(path);
        long length = before.Length, ticks = before.LastWriteTimeUtc.Ticks;
        using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        string hash = Convert.ToHexString(SHA256.HashData(input));
        var after = new FileInfo(path);
        if (after.Length != length || after.LastWriteTimeUtc.Ticks != ticks)
            throw new ImageException("sourceChangedError");
        return new FileVersion(length, ticks, hash);
    }
    public void Validate(string path)
    {
        if (Read(path) != this)
            throw new ImageException("sourceChangedError");
    }
}

public sealed record ImageInfo(PixelSize Size, int BitsPerComponent, int Orientation, string Format, FileVersion Version);
public sealed record Photo(Guid Id, string Path, ImageInfo Info);
public sealed record PhotoIssue(string Path, string Message, bool CanRetry);
public sealed record ExportResult(IReadOnlyList<string> Outputs, IReadOnlyList<PhotoIssue> Issues, bool Canceled);
public sealed record BatchProgress(int Completed, int Total);
public interface IImageProcessor
{
    ImageInfo Inspect(string path);
    byte[] Preview(string path, int maximumEdge, FileVersion? expected = null);
    void Export(string input, string output, BorderSettings settings, FileVersion expected, CancellationToken cancellationToken);
}

public sealed record Preset(Guid Id, string Name, BorderSettings Settings)
{
    public static readonly Guid MobileReferenceId = Guid.Parse("F09C703A-989B-4B4F-9FE9-7BD46CF14001");
}
public sealed class PresetStore(string path)
{
    public string Path { get; } = path;
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private sealed record Document(int Version, string GeometryContract, List<Preset> Presets);
    public IReadOnlyList<Preset> Load()
    {
        try
        {
            var document = JsonSerializer.Deserialize<Document>(File.ReadAllText(Path), Json);
            if (document is null || document.Version != 1 || document.GeometryContract != CanvasLayout.ContractId || document.Presets is null)
                return [];
            return document.Presets.Where(p => p is not null && !string.IsNullOrWhiteSpace(p.Name) && Valid(p.Settings)).ToArray();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or ArgumentException) { return []; }
    }
    private static bool Valid(BorderSettings settings)
    {
        try
        {
            settings.Validate();
            return true;
        }
        catch { return false; }
    }
    public void Save(IReadOnlyList<Preset> presets)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path))!);
        var temporary = Path + "." + Guid.NewGuid() + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(new Document(1, CanvasLayout.ContractId, presets.ToList()), Json));
            File.Move(temporary, Path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
