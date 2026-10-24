using System.Collections.ObjectModel;
using System.Text.Json;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BorderMuse.Core;
using BorderMuse.Imaging.Windows;
using Xunit;

namespace BorderMuse.PhotoParity.Tests;

public sealed class PhotoTests
{
    private static BitmapFrame Read(string path)
    {
        using var input = File.OpenRead(path);
        var frame = BitmapDecoder.Create(input, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
        frame.Freeze();
        return frame;
    }
    private static byte[] Srgb(BitmapFrame frame)
    {
        BitmapSource source = new FormatConvertedBitmap(frame, PixelFormats.Bgr32, null, 0);
        if (frame.ColorContexts?.Count > 0)
            source = new ColorConvertedBitmap(source, frame.ColorContexts[0], new ColorContext(PixelFormats.Bgr32), PixelFormats.Bgr32);
        byte[] pixels = new byte[frame.PixelWidth * frame.PixelHeight * 4];
        source.CopyPixels(pixels, frame.PixelWidth * 4, 0);
        return pixels;
    }
    private static byte[]? Profile(BitmapFrame frame)
    {
        if (frame.ColorContexts?.Count is not > 0) return null;
        using var input = frame.ColorContexts[0].OpenProfileStream();
        using var data = new MemoryStream(); input.CopyTo(data); return data.ToArray();
    }
    [Theory]
    [InlineData("river.jpg")]
    [InlineData("Landscape_6.jpg")]
    [InlineData("Portrait_8.jpg")]
    public void WindowsPhotoExportsAgreeWithMacDimensionsAndColor(string filename)
    {
        string root = Environment.GetEnvironmentVariable("BORDERMUSE_PHOTO_CORPUS") ?? throw new InvalidOperationException("Run the Public photo parity workflow or set BORDERMUSE_PHOTO_CORPUS.");
        string input = Path.Combine(root, "input", filename), reference = Path.Combine(root, "macos", filename);
        var processor = new ImageProcessor(); var info = processor.Inspect(input);
        var before = Read(input); var mac = Read(reference); var expected = Srgb(mac);
        var runs = new List<object>();
        foreach (bool keep in new[] { true, false })
        {
            string folder = Path.Combine(root, "windows", keep ? "kept" : "removed"); Directory.CreateDirectory(folder);
            string output = Path.Combine(folder, filename);
            var settings = new BorderSettings { Thickness = 10, KeepMetadata = keep };
            processor.Export(input, output, settings, info.Version, default);
            var result = processor.Inspect(output); var image = Read(output); var actual = Srgb(image);
            var layout = settings.Layout(info.Size);
            Assert.Equal(mac.PixelWidth, image.PixelWidth); Assert.Equal(mac.PixelHeight, image.PixelHeight);
            Assert.Equal(layout.Width, image.PixelWidth); Assert.Equal(layout.Height, image.PixelHeight);
            Assert.Equal(1, result.Orientation); Assert.Equal(info.BitsPerComponent, result.BitsPerComponent);
            Assert.Equal(Profile(before), Profile(image));
            double absolute = 0, squared = 0; long count = 0;
            for (int y = 0; y < info.Size.Height; y++)
                for (int x = 0; x < info.Size.Width; x++)
                {
                    int index = checked(((int)layout.Top + y) * image.PixelWidth + (int)layout.Left + x) * 4;
                    for (int c = 0; c < 3; c++) { int difference = actual[index + c] - expected[index + c]; absolute += Math.Abs(difference); squared += difference * difference; count++; }
                }
            double mean = absolute / count; double? psnr = squared == 0 ? null : 10 * Math.Log10(255 * 255 / (squared / count));
            // A regression bound for these named examples, not a universal color-quality claim.
            Assert.True(mean <= 5, $"{filename}: mean RGB difference from macOS is {mean:F3}.");
            Assert.True(psnr is null || psnr >= 30, $"{filename}: PSNR against macOS is {psnr:F2} dB.");
            foreach (int corner in new[] { 0, image.PixelWidth - 1, (image.PixelHeight - 1) * image.PixelWidth, image.PixelWidth * image.PixelHeight - 1 })
                for (int c = 0; c < 3; c++) Assert.InRange(actual[corner * 4 + c], (byte)250, (byte)255);
            var sourceTags = before.Metadata as BitmapMetadata; var tags = image.Metadata as BitmapMetadata;
            foreach (string query in new[] { "/app1/ifd/{ushort=271}", "/app1/ifd/{ushort=272}", "/app1/ifd/exif/{ushort=36867}" })
                Assert.Equal(keep ? sourceTags?.GetQuery(query)?.ToString() : null, tags?.GetQuery(query)?.ToString());
            info.Version.Validate(input);
            runs.Add(new { keepMetadata = keep, width = image.PixelWidth, height = image.PixelHeight, meanAbsoluteRgbDifference = mean, psnrDB = psnr, originalPreserved = true });
        }
        string reports = Path.Combine(root, "reports"); Directory.CreateDirectory(reports);
        File.WriteAllText(Path.Combine(reports, filename + ".json"), JsonSerializer.Serialize(runs, new JsonSerializerOptions { WriteIndented = true }));
    }
}
