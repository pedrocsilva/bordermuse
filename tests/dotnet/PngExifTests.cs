using System.Buffers.Binary;
using BorderMuse.Core;
using BorderMuse.Imaging.Windows;
using Xunit;

namespace BorderMuse.Tests;

public sealed class PngExifTests
{
    // Synthetic TIFF payloads with big/little endian entries, EXIF dimensions,
    // private camera data and a thumbnail link; CRCs generated independently.
    [Theory]
    [InlineData("iVBORw0KGgoAAAB4ZVhJZklJKgAIAAAABQAAAQQAAQAAAGUAAAABAQQAAQAAAEMAAAASAQMAAQAAAAYAAABphwQAAQAAAEoAAAAPAQIACgAAAGgAAAByAAAAAgACoAQAAQAAAGUAAAADoAQAAQAAAEMAAAAAAAAAUUEgQ2FtZXJhAAAAAAAAADmPVC0AAAAASUVORK5CYII=")]
    [InlineData("iVBORw0KGgoAAAB4ZVhJZk1NACoAAAAIAAUBAAAEAAAAAQAAAGUBAQAEAAAAAQAAAEMBEgADAAAAAQAGAACHaQAEAAAAAQAAAEoBDwACAAAACgAAAGgAAAByAAKgAgAEAAAAAQAAAGWgAwAEAAAAAQAAAEMAAAAAUUEgQ2FtZXJhAAAAAAAAAJWT5HEAAAAASUVORK5CYII=")]
    public void NormalizesFramingPreservesOtherDataAndRewritesChunk(string encoded)
    {
        byte[] png = Convert.FromBase64String(encoded);
        using var input = new MemoryStream(png);
        var before = PngExif.Read(input)!;
        Assert.Equal(6, PngExif.Orientation(before));
        byte[] after = PngExif.Normalize(before, 135, 107);
        Assert.Equal(1, PngExif.Orientation(after));
        uint Read(int offset) => after[0] == 'I' ? BinaryPrimitives.ReadUInt32LittleEndian(after.AsSpan(offset)) : BinaryPrimitives.ReadUInt32BigEndian(after.AsSpan(offset));
        Assert.Equal(135u, Read(18));
        Assert.Equal(107u, Read(30));
        Assert.Equal(135u, Read(84));
        Assert.Equal(107u, Read(96));
        Assert.Equal(0u, Read(70));
        Assert.Equal(before.AsSpan(104, 10).ToArray(), after.AsSpan(104, 10).ToArray());
        string path = Path.Combine(Path.GetTempPath(), "bordermuse-png-" + Guid.NewGuid());
        try
        {
            File.WriteAllBytes(path, png);
            PngExif.Replace(path, after);
            using (var result = File.OpenRead(path))
                Assert.Equal(after, PngExif.Read(result));
            PngExif.Replace(path, null);
            using (var result = File.OpenRead(path))
                Assert.Null(PngExif.Read(result));
            // Both corruption and out-of-bounds TIFF offsets fail closed.
            after[4] = after[5] = after[6] = after[7] = 255;
            Assert.Throws<OverflowException>(() => PngExif.Orientation(after));
            png[^13] ^= 1;
            using var corrupt = new MemoryStream(png);
            Assert.Throws<ImageException>(() => PngExif.Read(corrupt));
        }
        finally { File.Delete(path); }
    }
}
