using System.Security.Cryptography;
using System.Text.Json;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BorderMuse.Core;
using BorderMuse.Geometry;
using BorderMuse.Imaging.Windows;
using Xunit;

namespace BorderMuse.Windows.Tests;

public sealed class MobileGeometryTests
{
    [Fact]
    public void FullSizeThroughReductionAndRenderingMatchesEveryMeasuredMargin()
    {
        using var corpus = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "conformance-v1.json")));
        using var pipeline = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "mobile-export-v1.json")));
        var cases = corpus.RootElement.GetProperty("cases");
        Assert.Equal(20, cases.GetArrayLength());
        var root = Path.Combine(Path.GetTempPath(), "bordermuse-mobile-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        try
        {
            var processor = new ImageProcessor();
            foreach (var baseline in pipeline.RootElement.GetProperty("baselines").EnumerateObject())
            {
                int width = baseline.Value.GetProperty("sourceWidth").GetInt32(), height = baseline.Value.GetProperty("sourceHeight").GetInt32();
                string input = Path.Combine(root, baseline.Name + ".png");
                byte[] pixels = new byte[width * height * 3];
                var image = BitmapSource.Create(width, height, 96, 96, PixelFormats.Rgb24, null, pixels, width * 3);
                var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
                using (var file = File.Create(input)) encoder.Save(file);
                byte[] originalHash = SHA256.HashData(File.ReadAllBytes(input));
                foreach (var sample in cases.EnumerateArray().Where(c => c.GetProperty("source_file").GetString()!.StartsWith(baseline.Name + "_", StringComparison.Ordinal)))
                {
                    var source = sample.GetProperty("input"); var ratio = source.GetProperty("ratio");
                    var settings = new BorderSettings().ApplyingMobileReference() with
                    {
                        Ratio = $"{ratio[0].GetInt32()}:{ratio[1].GetInt32()}", Thickness = source.GetProperty("thickness").GetInt32(), KeepMetadata = false
                    };
                    Assert.Equal(pipeline.RootElement.GetProperty("photoLongEdge").GetInt32(), settings.LongEdge);
                    var info = processor.Inspect(input);
                    var prepared = new PixelSize(baseline.Value.GetProperty("preparedWidth").GetInt32(), baseline.Value.GetProperty("preparedHeight").GetInt32());
                    Assert.Equal(prepared, settings.PreparedSize(info.Size));
                    Assert.Equal(prepared, new PixelSize(source.GetProperty("width").GetInt32(), source.GetProperty("height").GetInt32()));
                    var e = sample.GetProperty("expected");
                    var expected = new CanvasLayout(e.GetProperty("width").GetInt32(), e.GetProperty("height").GetInt32(), e.GetProperty("left").GetInt32(), e.GetProperty("right").GetInt32(), e.GetProperty("top").GetInt32(), e.GetProperty("bottom").GetInt32());
                    Assert.Equal(expected, settings.Layout(info.Size));
                    string output = Path.Combine(root, sample.GetProperty("source_file").GetString() + ".png");
                    processor.Export(input, output, settings, info.Version, default);
                    Assert.Equal(expected, Measure(output));
                }
                Assert.Equal(originalHash, SHA256.HashData(File.ReadAllBytes(input)));
            }
        }
        finally { Directory.Delete(root, true); }
    }
    private static CanvasLayout Measure(string path)
    {
        using var file = File.OpenRead(path);
        var decoded = BitmapDecoder.Create(file, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
        var frame = new FormatConvertedBitmap(decoded, PixelFormats.Rgb24, null, 0);
        int w = frame.PixelWidth, h = frame.PixelHeight;
        byte[] pixels = new byte[w * h * 3]; frame.CopyPixels(pixels, w * 3, 0);
        int left = w, right = -1, top = h, bottom = -1;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                if (pixels[(y * w + x) * 3] < 128)
                {
                    left = Math.Min(left, x); right = Math.Max(right, x); top = Math.Min(top, y); bottom = Math.Max(bottom, y);
                }
        Assert.True(right >= left);
        return new(w, h, left, w - right - 1, top, h - bottom - 1);
    }
}
