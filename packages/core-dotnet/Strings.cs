using System.Globalization;
using System.Text.Json;

namespace BorderMuse.Core;

public static class Strings
{
    public static readonly CultureInfo Culture = CultureInfo.GetCultureInfo("en-US");
    private static readonly Dictionary<string, string> Catalog = Load();
    private static Dictionary<string, string> Load()
    {
        using var stream = typeof(Strings).Assembly.GetManifestResourceStream("BorderMuse.Core.Resources.en-US.json")
            ?? throw new InvalidOperationException("Missing en-US resources.");
        return JsonSerializer.Deserialize<Dictionary<string, string>>(stream)!;
    }
    public static string Text(string key) => Catalog.TryGetValue(key, out var value) ? value : throw new KeyNotFoundException(key);
    public static string Format(string key, params object[] values) => string.Format(Culture, Text(key), values);
    public static string Message(Exception error) => error switch
    {
        ImageException image => Text(image.ResourceKey),
        OverflowException => Text("allocationError"),
        _ => Text("genericExportError")
    };
}

public sealed class ImageException(string resourceKey, Exception? inner = null) : Exception(Strings.Text(resourceKey), inner)
{
    public string ResourceKey { get; } = resourceKey;
}
