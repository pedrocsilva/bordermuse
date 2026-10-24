using System.Collections.ObjectModel;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BorderMuse.Core;
using BorderMuse.Geometry;
using BorderMuse.Imaging.Windows;
using Xunit;

namespace BorderMuse.Windows.Tests;

public sealed class ImageTests : IDisposable
{
    private readonly string root = Path.Combine(Path.GetTempPath(), "bordermuse-images-" + Guid.NewGuid());
    private readonly ImageProcessor processor = new();
    public ImageTests() => Directory.CreateDirectory(root);
    public void Dispose() => Directory.Delete(root, true);
    private string Fixture(string format = "png", int orientation = 1, int bits = 8, bool metadata = true, int frames = 1)
    {
        string path = Path.Combine(root, Guid.NewGuid() + "." + (format == "jpeg" ? "jpg" : format));
        PixelFormat pixelFormat = bits == 16 ? PixelFormats.Rgb48 : PixelFormats.Rgb24;
        int stride = 100 * 3 * (bits / 8);
        byte[] pixels = new byte[stride * 80];
        for (int y = 0; y < 80; y++)
        for (int x = 0; x < 100; x++)
        for (int c = 0; c < 3; c++)
        {
            int index = y * stride + x * 3 * (bits / 8) + c * (bits / 8);
            byte value = (byte)(c == 0 ? (x < 50 ? 210 : 30) : c == 1 ? (y < 40 ? 150 : 20) : 80);
            pixels[index] = value;
            if (bits == 16)
                pixels[index + 1] = value;
        }
        var bitmap = BitmapSource.Create(100, 80, 96, 96, pixelFormat, null, pixels, stride);
        bitmap.Freeze();
        BitmapEncoder encoder = format switch
        {
            "jpeg" => new JpegBitmapEncoder { QualityLevel = 100 },
            "tiff" => new TiffBitmapEncoder(),
            _ => new PngBitmapEncoder()
        };
        BitmapMetadata? tags = null;
        if (metadata && format != "png")
        {
            tags = new BitmapMetadata(format == "jpeg" ? "jpg" : "tiff");
            string prefix = format == "jpeg" ? "/app1/ifd" : "/ifd";
            tags.SetQuery(prefix + "/{ushort=274}", (ushort)orientation);
            tags.SetQuery(prefix + "/{ushort=271}", "Synthetic camera");
            tags.SetQuery(prefix + "/exif/{ushort=36867}", "2026:10:24 12:00:00");
        }
        for (int i = 0; i < frames; i++)
            encoder.Frames.Add(BitmapFrame.Create(bitmap, null, tags, new ReadOnlyCollection<ColorContext>([new ColorContext(pixelFormat)])));
        using (var stream = File.Create(path))
            encoder.Save(stream);
        return path;
    }
    private static BitmapFrame Read(string path)
    {
        using var stream = File.OpenRead(path);
        var frame = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
        frame.Freeze();
        return frame;
    }
    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(4)]
    [InlineData(5)]
    [InlineData(6)]
    [InlineData(7)]
    [InlineData(8)]
    public void EveryExifOrientationIsNormalizedAndPlaced(int orientation)
    {
        string input = Fixture("tiff", orientation);
        var info = processor.Inspect(input);
        Assert.Equal(orientation, info.Orientation);
        var expected = orientation >= 5 ? new PixelSize(80, 100) : new PixelSize(100, 80);
        Assert.Equal(expected, info.Size);
        string output = Path.Combine(root, "out.tiff");
        var settings = new BorderSettings { Ratio = "1:1", Thickness = 10 };
        processor.Export(input, output, settings, info.Version, default);
        var actual = processor.Inspect(output);
        var layout = settings.Layout(info.Size);
        Assert.Equal(new PixelSize(layout.Width, layout.Height), actual.Size);
        Assert.Equal(1, actual.Orientation);
        // Independent source-coordinate expectations for the top-left content pixel.
        var source = new FormatConvertedBitmap(Read(input), PixelFormats.Rgb24, null, 0);
        byte[] original = new byte[100 * 80 * 3];
        source.CopyPixels(original, 300, 0);
        var (sx, sy) = orientation switch
        {
            2 => (99, 0),
            3 => (99, 79),
            4 => (0, 79),
            5 => (0, 0),
            6 => (0, 79),
            7 => (99, 79),
            8 => (99, 0),
            _ => (0, 0)
        };
        var rendered = new FormatConvertedBitmap(Read(output), PixelFormats.Rgb24, null, 0);
        int stride = rendered.PixelWidth * 3;
        byte[] result = new byte[stride * rendered.PixelHeight];
        rendered.CopyPixels(result, stride, 0);
        int start = checked((int)layout.Top) * stride + checked((int)layout.Left) * 3;
        Assert.Equal(original.AsSpan((sy * 100 + sx) * 3, 3).ToArray(), result.AsSpan(start, 3).ToArray());
        Assert.Equal(new byte[] { 255, 255, 255 }, result.AsSpan(0, 3).ToArray());
    }
    [Theory]
    [InlineData("jpeg", 8)]
    [InlineData("png", 8)]
    [InlineData("tiff", 8)]
    [InlineData("png", 16)]
    [InlineData("tiff", 16)]
    public void FormatsDepthProfilesAndMetadataPolicy(string format, int bits)
    {
        string input = Fixture(format, bits: bits);
        byte[] original = File.ReadAllBytes(input);
        var info = processor.Inspect(input);
        Assert.Equal(bits, info.BitsPerComponent);
        foreach (bool keep in new[] { true, false })
        {
            string output = Path.Combine(root, "out-" + keep + Path.GetExtension(input));
            processor.Export(input, output, new BorderSettings { KeepMetadata = keep }, info.Version, default);
            var actual = processor.Inspect(output);
            Assert.Equal(bits, actual.BitsPerComponent);
            Assert.Equal(info.Format, actual.Format);
            var frame = Read(output);
            Assert.NotEmpty(frame.ColorContexts);
            if (format != "png")
            {
                string query = format == "jpeg" ? "/app1/ifd/{ushort=271}" : "/ifd/{ushort=271}";
                var tags = (BitmapMetadata)frame.Metadata;
                Assert.Equal(keep ? "Synthetic camera" : null, tags?.GetQuery(query));
            }
        }
        Assert.Equal(original, File.ReadAllBytes(input));
        Assert.Empty(Directory.GetFiles(root, ".bordermuse-*"));
    }
    [Fact]
    public void NoOpCopiesBytesAndFailuresNeverOverwrite()
    {
        string input = Fixture();
        var info = processor.Inspect(input);
        string output = Path.Combine(root, "output.png");
        var options = new BorderSettings { Thickness = 0 };
        processor.Export(input, output, options, info.Version, default);
        Assert.Equal(File.ReadAllBytes(input), File.ReadAllBytes(output));
        Assert.Throws<IOException>(() => processor.Export(input, output, new(), info.Version, default));
        Assert.Throws<ImageException>(() => processor.Export(input, input, new(), info.Version, default));
        File.AppendAllText(input, "changed");
        Assert.Throws<ImageException>(() => processor.Export(input, Path.Combine(root, "changed.png"), new(), info.Version, default));
        Assert.Empty(Directory.GetFiles(root, ".bordermuse-*"));
    }
    [Fact]
    public void CancellationResizeAndUnsupportedInput()
    {
        string input = Fixture("tiff", bits: 16);
        var info = processor.Inspect(input);
        string output = Path.Combine(root, "resized.tiff");
        processor.Export(input, output, new BorderSettings { ReduceSize = true, LongEdge = 51 }, info.Version, default);
        Assert.Equal(new PixelSize(55, 45), processor.Inspect(output).Size);
        Assert.Equal(16, processor.Inspect(output).BitsPerComponent);
        using var cancel = new CancellationTokenSource();
        cancel.Cancel();
        Assert.Throws<OperationCanceledException>(() => processor.Export(input, Path.Combine(root, "canceled.tiff"), new(), info.Version, cancel.Token));
        Assert.Empty(Directory.GetFiles(root, ".bordermuse-*"));
        Assert.Throws<ImageException>(() => processor.Inspect(Fixture("tiff", frames: 2)));
        string invalid = Path.Combine(root, "invalid.png");
        File.WriteAllText(invalid, "synthetic invalid input");
        Assert.Throws<ImageException>(() => processor.Inspect(invalid));
        Assert.NotEmpty(processor.Preview(input, 30, info.Version));
    }
}
