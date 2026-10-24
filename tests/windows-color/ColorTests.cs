using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BorderMuse.Core;
using BorderMuse.Imaging.Windows;
using Xunit;

namespace BorderMuse.Color.Tests;

public sealed class ColorTests
{
    private const string Marker = "Synthetic BorderMuse metadata";
    private static BitmapFrame Read(string path)
    {
        using var stream = File.OpenRead(path);
        var frame = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
        frame.Freeze();
        return frame;
    }
    private static byte[]? Profile(BitmapFrame image)
    {
        if (image.ColorContexts is null || image.ColorContexts.Count == 0)
            return null;
        using var input = image.ColorContexts[0].OpenProfileStream();
        using var output = new MemoryStream();
        input.CopyTo(output);
        return output.ToArray();
    }
    private static byte[] Pixel(BitmapSource image, int x, int y)
    {
        var source = new FormatConvertedBitmap(image, PixelFormats.Rgb48, null, 0);
        byte[] pixel = new byte[6];
        source.CopyPixels(new System.Windows.Int32Rect(x, y, 1, 1), pixel, 6, 0);
        return pixel;
    }
    private static bool HasMarker(string path)
    {
        byte[] data = File.ReadAllBytes(path);
        if (Encoding.UTF8.GetString(data).Contains(Marker))
            return true;
        if (!data.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }))
            return false;
        for (int i = 8; i + 12 <= data.Length;)
        {
            int count = checked((int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(i, 4)));
            string type = Encoding.ASCII.GetString(data, i + 4, 4);
            if (type == "iTXt")
            {
                var chunk = data.AsSpan(i + 8, count).ToArray();
                int end = Array.IndexOf(chunk, (byte)0);
                int start = end + 3;
                start = Array.IndexOf(chunk, (byte)0, start) + 1;
                start = Array.IndexOf(chunk, (byte)0, start) + 1;
                if (end >= 0 && start > 0 && chunk[end + 1] == 1)
                {
                    using var compressed = new MemoryStream(chunk, start, chunk.Length - start);
                    using var zip = new ZLibStream(compressed, CompressionMode.Decompress);
                    using var reader = new StreamReader(zip);
                    if (reader.ReadToEnd().Contains(Marker))
                        return true;
                }
            }
            i = checked(i + 12 + count);
        }
        return false;
    }
    [Theory]
    [InlineData("sRGB-8.jpg")]
    [InlineData("sRGB-8.png")]
    [InlineData("sRGB-16.png")]
    [InlineData("sRGB-8.tiff")]
    [InlineData("sRGB-16.tiff")]
    [InlineData("P3-8.jpg")]
    [InlineData("P3-8.png")]
    [InlineData("P3-16.png")]
    [InlineData("P3-8.tiff")]
    [InlineData("P3-16.tiff")]
    public void SharedSrgbP3DepthAndOpaqueXmpRoundTrips(string filename)
    {
        string inputFolder = Environment.GetEnvironmentVariable("BORDERMUSE_COLOR_FIXTURES") ?? throw new InvalidOperationException("Set BORDERMUSE_COLOR_FIXTURES to the generated shared codec corpus.");
        string outputFolder = Path.Combine(Path.GetTempPath(), "bordermuse-color-" + Guid.NewGuid());
        Directory.CreateDirectory(outputFolder);
        try
        {
            Assert.Equal(10, Directory.GetFiles(inputFolder).Length);
            var processor = new ImageProcessor();
            string input = Path.Combine(inputFolder, filename);
            {
                var info = processor.Inspect(input);
                var before = Read(input);
                if (filename.StartsWith("P3")) Assert.NotNull(Profile(before));
                Assert.True(HasMarker(input), "Source XMP missing: " + input);
                foreach (bool keep in new[] { true, false })
                {
                    string output = Path.Combine(outputFolder, keep + Path.GetFileName(input));
                    processor.Export(input, output, new BorderSettings { Ratio = "5:4", Thickness = 7, KeepMetadata = keep }, info.Version, default);
                    var after = Read(output);
                    Assert.Equal(107, after.PixelWidth);
                    Assert.Equal(85, after.PixelHeight);
                    Assert.Equal(info.BitsPerComponent, processor.Inspect(output).BitsPerComponent);
                    Assert.Equal(Profile(before), Profile(after));
                    Assert.Equal(keep, HasMarker(output));
                    byte[] a = Pixel(before, 50, 33), b = Pixel(after, 53, 42);
                    for (int c = 0; c < 3; c++)
                        Assert.InRange(Math.Abs(BinaryPrimitives.ReadUInt16LittleEndian(a.AsSpan(c * 2, 2)) - BinaryPrimitives.ReadUInt16LittleEndian(b.AsSpan(c * 2, 2))), 0, info.BitsPerComponent == 16 ? 2 : 514);
                    if (info.BitsPerComponent == 16)
                        Assert.Contains(Enumerable.Range(0, 3).Select(c => BinaryPrimitives.ReadUInt16LittleEndian(b.AsSpan(c * 2, 2))), v => v % 257 != 0);
                }
            }
        }
        finally { Directory.Delete(outputFolder, true); }
    }
}
