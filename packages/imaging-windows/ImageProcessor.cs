using System.Buffers.Binary;
using System.Collections.ObjectModel;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BorderMuse.Core;
using BorderMuse.Geometry;

namespace BorderMuse.Imaging.Windows;

/// <summary>WIC-backed Windows adapter. Geometry never depends on these APIs.</summary>
public sealed class ImageProcessor : IImageProcessor
{
    private const long MaximumWorkingBytes = 1_073_741_824;
    private static FileStream Open(string path) => new(path, FileMode.Open, FileAccess.Read, FileShare.Read);
    private static BitmapDecoder Decoder(Stream stream) => BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.None);
    private static string Format(BitmapDecoder decoder) => decoder switch
    {
        JpegBitmapDecoder => "jpeg",
        PngBitmapDecoder => "png",
        TiffBitmapDecoder => "tiff",
        _ => throw new ImageException("unsupportedError")
    };
    private static int Depth(BitmapSource image) => image.Format.BitsPerPixel switch
    {
        8 or 24 or 32 => 8,
        48 or 64 => 16,
        16 when image.Format == PixelFormats.Gray16 => 16,
        _ => throw new ImageException("unsupportedError")
    };
    private static int Orientation(BitmapMetadata? metadata, string format)
    {
        string path = format == "jpeg" ? "/app1/ifd/{ushort=274}" : format == "tiff" ? "/ifd/{ushort=274}" : "/eXIf/ifd/{ushort=274}";
        try
        {
            return metadata?.GetQuery(path) is { } value ? Convert.ToInt32(value) : 1;
        }
        catch (NotSupportedException) { return 1; }
    }
    private static ImageInfo Info(BitmapDecoder decoder, FileVersion version)
    {
        string format = Format(decoder);
        if (decoder.Frames.Count != 1)
            throw new ImageException("unsupportedError");
        var frame = decoder.Frames[0];
        int orientation = Orientation(frame.Metadata as BitmapMetadata, format);
        if (orientation is < 1 or > 8)
            throw new ImageException("unsupportedError");
        // A gain-map XMP flag must not silently become an SDR export.
        if (frame.Metadata is BitmapMetadata metadata)
        {
            foreach (string query in new[] { "/xmp/hdrgm:Version", "/xmp/HDRGainMap:Version" })
                try
                {
                    if (metadata.ContainsQuery(query))
                        throw new ImageException("unsupportedError");
                }
                catch (NotSupportedException) { }
        }
        return new ImageInfo(new PixelSize(orientation >= 5 ? frame.PixelHeight : frame.PixelWidth,
            orientation >= 5 ? frame.PixelWidth : frame.PixelHeight), Depth(frame), orientation, format, version);
    }
    public ImageInfo Inspect(string path)
    {
        try
        {
            var version = FileVersion.Read(path);
            using var stream = Open(path);
            var info = Info(Decoder(stream), version);
            version.Validate(path);
            return info;
        }
        catch (Exception error) when (error is IOException or NotSupportedException or System.IO.FileFormatException)
        {
            throw new ImageException("unreadableError", error);
        }
    }
    public byte[] Preview(string path, int maximumEdge, FileVersion? expected = null)
    {
        if (maximumEdge <= 0)
            throw new ArgumentOutOfRangeException(nameof(maximumEdge));
        var version = FileVersion.Read(path);
        if (expected is not null && version != expected)
            throw new ImageException("sourceChangedError");
        using var stream = Open(path);
        var decoder = Decoder(stream);
        var info = Info(decoder, version);
        var size = new BorderSettings { ReduceSize = true, LongEdge = Math.Min(maximumEdge, 100_000) }.PreparedSize(info.Size);
        var (image, contexts) = Render(decoder.Frames[0], info, size, new CanvasLayout(size.Width, size.Height, 0, 0, 0, 0), CancellationToken.None);
        BitmapSource display = image;
        if (contexts?.Count > 0)
            display = new ColorConvertedBitmap(image, contexts[0], new ColorContext(PixelFormats.Bgra32), PixelFormats.Bgra32);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(display));
        using var output = new MemoryStream();
        encoder.Save(output);
        version.Validate(path);
        return output.ToArray();
    }
    public void Export(string input, string output, BorderSettings settings, FileVersion expected, CancellationToken cancellationToken)
    {
        settings.Validate();
        if (string.Equals(Path.GetFullPath(input), Path.GetFullPath(output), StringComparison.OrdinalIgnoreCase))
            throw new ImageException("sameFileError");
        if (File.Exists(output))
            throw new IOException(Strings.Text("writeError"));
        var info = Inspect(input);
        if (info.Version != expected)
            throw new ImageException("sourceChangedError");
        var content = settings.PreparedSize(info.Size);
        var layout = settings.Layout(info.Size);
        long sourcePixels = checked(info.Size.Width * info.Size.Height), pixels = checked(layout.Width * layout.Height);
        if (layout.Width > int.MaxValue || layout.Height > int.MaxValue || checked((2 * sourcePixels + pixels) * (info.BitsPerComponent == 16 ? 8 : 4)) > MaximumWorkingBytes)
            throw new ImageException("allocationError");
        string temp = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(output))!, ".bordermuse-" + Guid.NewGuid() + ".tmp");
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (settings.Thickness == 0 && settings.Ratio == "original" && content == info.Size && settings.KeepMetadata)
                File.Copy(input, temp, false);
            else
            {
                using var source = Open(input);
                var decoder = Decoder(source);
                var frame = decoder.Frames[0];
                var (rendered, contexts) = Render(frame, info, content, layout, cancellationToken);
                BitmapMetadata? metadata = settings.KeepMetadata ? (frame.Metadata as BitmapMetadata)?.Clone() : null;
                NormalizeMetadata(metadata, info.Format, (int)layout.Width, (int)layout.Height);
                BitmapEncoder encoder = info.Format switch
                {
                    "jpeg" => new JpegBitmapEncoder { QualityLevel = settings.Quality },
                    "png" => new PngBitmapEncoder(),
                    "tiff" => new TiffBitmapEncoder { Compression = TiffCompressOption.Zip },
                    _ => throw new ImageException("unsupportedError")
                };
                encoder.Frames.Add(BitmapFrame.Create(rendered, null, metadata, contexts));
                using var destination = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                encoder.Save(destination);
                destination.Flush(true);
            }
            cancellationToken.ThrowIfCancellationRequested();
            expected.Validate(input);
            File.Move(temp, output, false);
        }
        catch (OutOfMemoryException error) { throw new ImageException("allocationError", error); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    private static void NormalizeMetadata(BitmapMetadata? metadata, string format, int width, int height)
    {
        if (metadata is null)
            return;
        string prefix = format == "jpeg" ? "/app1/ifd" : format == "tiff" ? "/ifd" : "/eXIf/ifd";
        foreach (var (query, value) in new (string, object)[] {
            (prefix+"/{ushort=274}",(ushort)1), (prefix+"/{ushort=256}",(uint)width), (prefix+"/{ushort=257}",(uint)height),
            (prefix+"/exif/{ushort=40962}",(uint)width),(prefix+"/exif/{ushort=40963}",(uint)height) })
        {
            // Do not create codec-specific metadata blocks which the input did not contain.
            if (format != "png" || metadata.ContainsQuery(query))
                metadata.SetQuery(query, value);
        }
        foreach (string query in new[] { prefix + "/thumbnail", "/xmp/xmp:Thumbnails" })
            if (metadata.ContainsQuery(query))
                metadata.RemoveQuery(query);
    }
    private static bool Rgb(ColorContext context)
    {
        using var stream = context.OpenProfileStream();
        Span<byte> header = stackalloc byte[20];
        return stream.Read(header) == 20 && header[16] == (byte)'R' && header[17] == (byte)'G' && header[18] == (byte)'B';
    }
    private static (BitmapSource, ReadOnlyCollection<ColorContext>?) Render(BitmapFrame frame, ImageInfo info, PixelSize content, CanvasLayout layout, CancellationToken token)
    {
        int depth = info.BitsPerComponent, channelBytes = depth / 8, bpp = 3 * channelBytes;
        var workingFormat = depth == 16 ? PixelFormats.Rgba64 : PixelFormats.Bgra32;
        ReadOnlyCollection<ColorContext>? contexts = frame.ColorContexts;
        BitmapSource source = frame;
        if (contexts?.Count > 0 && !Rgb(contexts[0]))
        {
            var target = new ColorContext(workingFormat);
            source = new ColorConvertedBitmap(frame, contexts[0], target, workingFormat);
            contexts = new ReadOnlyCollection<ColorContext>([target]);
        }
        if (source.Format != workingFormat)
            source = new FormatConvertedBitmap(source, workingFormat, null, 0);
        int sw = source.PixelWidth, sh = source.PixelHeight, rawStride = checked(sw * 4 * channelBytes);
        var raw = new byte[checked(rawStride * sh)];
        source.CopyPixels(raw, rawStride, 0);
        int ow = checked((int)info.Size.Width), oh = checked((int)info.Size.Height);
        var oriented = new byte[checked(ow * oh * bpp)];
        for (int y = 0; y < oh; y++)
        {
            token.ThrowIfCancellationRequested();
            for (int x = 0; x < ow; x++)
            {
                var (sx, sy) = info.Orientation switch
                {
                    2 => (sw - 1 - x, y),
                    3 => (sw - 1 - x, sh - 1 - y),
                    4 => (x, sh - 1 - y),
                    5 => (y, x),
                    6 => (y, sh - 1 - x),
                    7 => (sw - 1 - y, sh - 1 - x),
                    8 => (sw - 1 - y, x),
                    _ => (x, y)
                };
                int read = sy * rawStride + sx * 4 * channelBytes, write = (y * ow + x) * bpp;
                if (depth == 8)
                {
                    int a = raw[read + 3];
                    for (int c = 0; c < 3; c++)
                        oriented[write + c] = (byte)((raw[read + 2 - c] * a + 255 * (255 - a) + 127) / 255);
                }
                else
                {
                    uint a = BinaryPrimitives.ReadUInt16LittleEndian(raw.AsSpan(read + 6, 2));
                    for (int c = 0; c < 3; c++)
                    {
                        uint value = BinaryPrimitives.ReadUInt16LittleEndian(raw.AsSpan(read + c * 2, 2));
                        BinaryPrimitives.WriteUInt16LittleEndian(oriented.AsSpan(write + c * 2, 2), (ushort)((value * a + 65535u * (65535u - a) + 32767u) / 65535u));
                    }
                }
            }
        }
        int cw = checked((int)content.Width), ch = checked((int)content.Height);
        byte[] prepared = cw == ow && ch == oh ? oriented : Resize(oriented, ow, oh, cw, ch, depth, token);
        int width = checked((int)layout.Width), height = checked((int)layout.Height), stride = checked(width * bpp);
        var pixels = new byte[checked(stride * height)];
        Array.Fill(pixels, (byte)255);
        for (int y = 0; y < ch; y++)
        {
            token.ThrowIfCancellationRequested();
            Buffer.BlockCopy(prepared, y * cw * bpp, pixels, checked(((int)layout.Top + y) * stride + (int)layout.Left * bpp), cw * bpp);
        }
        var bitmap = BitmapSource.Create(width, height, 96, 96, depth == 16 ? PixelFormats.Rgb48 : PixelFormats.Rgb24, null, pixels, stride);
        bitmap.Freeze();
        return (bitmap, contexts);
    }
    // Separable bilinear filtering preserves 16-bit samples and exact prepared dimensions.
    // Filter/color parity is validated independently of geometry; encoded bytes may differ from Apple.
    private static byte[] Resize(byte[] input, int sw, int sh, int dw, int dh, int depth, CancellationToken token)
    {
        int bytes = depth / 8, bpp = 3 * bytes;
        var output = new byte[checked(dw * dh * bpp)];
        int Sample(int x, int y, int c)
        {
            int i = (y * sw + x) * bpp + c * bytes;
            return bytes == 1 ? input[i] : BinaryPrimitives.ReadUInt16LittleEndian(input.AsSpan(i, 2));
        }
        for (int y = 0; y < dh; y++)
        {
            token.ThrowIfCancellationRequested();
            double sy = Math.Clamp((y + 0.5) * sh / dh - 0.5, 0, sh - 1);
            int y0 = (int)sy, y1 = Math.Min(y0 + 1, sh - 1);
            double fy = sy - y0;
            for (int x = 0; x < dw; x++)
            {
                double sx = Math.Clamp((x + 0.5) * sw / dw - 0.5, 0, sw - 1);
                int x0 = (int)sx, x1 = Math.Min(x0 + 1, sw - 1);
                double fx = sx - x0;
                for (int c = 0; c < 3; c++)
                {
                    int value = (int)Math.Round((Sample(x0, y0, c) * (1 - fx) + Sample(x1, y0, c) * fx) * (1 - fy) + (Sample(x0, y1, c) * (1 - fx) + Sample(x1, y1, c) * fx) * fy);
                    int i = (y * dw + x) * bpp + c * bytes;
                    if (bytes == 1)
                        output[i] = (byte)value;
                    else
                        BinaryPrimitives.WriteUInt16LittleEndian(output.AsSpan(i, 2), (ushort)value);
                }
            }
        }
        return output;
    }
}
