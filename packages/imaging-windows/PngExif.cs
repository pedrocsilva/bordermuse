using System.Buffers.Binary;
using System.Text;
using System.IO.Compression;
using BorderMuse.Core;

namespace BorderMuse.Imaging.Windows;

// WIC preserves PNG eXIf as an opaque chunk but does not expose its orientation.
// Read/normalize only the TIFF framing tags; leave camera/GPS/private data intact.
internal static class PngExif
{
    private static readonly byte[] Signature = [137, 80, 78, 71, 13, 10, 26, 10];
    internal static byte[]? Read(Stream stream)
    {
        long position = stream.Position;
        try
        {
            stream.Position = 0;
            Span<byte> signature = stackalloc byte[8];
            stream.ReadExactly(signature);
            if (!signature.SequenceEqual(Signature))
                throw new ImageException("unreadableError");
            byte[]? result = null;
            Span<byte> crc = stackalloc byte[4];
            foreach (var chunk in Chunks(stream))
            {
                if (chunk.Type != "eXIf")
                    continue;
                if (result is not null || chunk.Length > 16 * 1024 * 1024)
                    throw new ImageException("unsupportedError");
                result = new byte[chunk.Length];
                stream.ReadExactly(result);
                stream.ReadExactly(crc);
                if (BinaryPrimitives.ReadUInt32BigEndian(crc) != Crc(result))
                    throw new ImageException("unreadableError");
                _ = new Tiff(result).Orientation;
            }
            return result;
        }
        finally { stream.Position = position; }
    }
    internal static int Orientation(byte[]? data) => data is null ? 1 : new Tiff(data).Orientation;
    internal static byte[] Normalize(byte[] data, int width, int height)
    {
        byte[] result = (byte[])data.Clone();
        new Tiff(result).Normalize(width, height);
        return result;
    }
    private sealed class Tiff
    {
        private readonly byte[] data;
        private readonly bool little;
        private readonly int root;
        internal Tiff(byte[] bytes)
        {
            data = bytes;
            Check(0, 8);
            little = data[0] == 'I' && data[1] == 'I';
            if (!little && !(data[0] == 'M' && data[1] == 'M') || U16(2) != 42)
                throw new ImageException("unreadableError");
            root = checked((int)U32(4));
            _ = Entries(root).ToArray();
        }
        private void Check(int offset, int length)
        {
            if (offset < 0 || length < 0 || offset > data.Length - length)
                throw new ImageException("unreadableError");
        }
        private ushort U16(int offset)
        {
            Check(offset, 2);
            return little ? BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(offset)) : BinaryPrimitives.ReadUInt16BigEndian(data.AsSpan(offset));
        }
        private uint U32(int offset)
        {
            Check(offset, 4);
            return little ? BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset)) : BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(offset));
        }
        private void Put16(int offset, ushort value)
        {
            Check(offset, 2);
            if (little)
                BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(offset), value);
            else
                BinaryPrimitives.WriteUInt16BigEndian(data.AsSpan(offset), value);
        }
        private void Put32(int offset, uint value)
        {
            Check(offset, 4);
            if (little)
                BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(offset), value);
            else
                BinaryPrimitives.WriteUInt32BigEndian(data.AsSpan(offset), value);
        }
        private IEnumerable<int> Entries(int offset)
        {
            int count = U16(offset);
            Check(offset, checked(2 + count * 12 + 4));
            for (int i = 0; i < count; i++)
                yield return offset + 2 + i * 12;
        }
        private uint Number(int entry)
        {
            if (U32(entry + 4) != 1)
                throw new ImageException("unreadableError");
            return U16(entry + 2) switch
            {
                3 => U16(entry + 8),
                4 => U32(entry + 8),
                _ => throw new ImageException("unreadableError")
            };
        }
        internal int Orientation => Entries(root).Where(e => U16(e) == 274).Select(e => checked((int)Number(e))).DefaultIfEmpty(1).Single();
        internal void Normalize(int width, int height)
        {
            foreach (int entry in Entries(root))
            {
                ushort tag = U16(entry);
                if (tag == 274)
                {
                    Put16(entry + 2, 3);
                    Put32(entry + 4, 1);
                    Put32(entry + 8, 0);
                    Put16(entry + 8, 1);
                }
                if (tag is 256 or 257)
                    Dimension(entry, tag == 256 ? width : height);
                if (tag == 34665)
                    foreach (int exif in Entries(checked((int)Number(entry))))
                        if (U16(exif) is 40962 or 40963)
                            Dimension(exif, U16(exif) == 40962 ? width : height);
            }
            // Detach the old thumbnail IFD; its pixels/dimensions describe the source.
            Put32(root + 2 + U16(root) * 12, 0);
        }
        private void Dimension(int entry, int value)
        {
            Put16(entry + 2, 4);
            Put32(entry + 4, 1);
            Put32(entry + 8, checked((uint)value));
        }
    }
    private readonly record struct Chunk(long Start, int Length, string Type);
    private static IEnumerable<Chunk> Chunks(Stream stream)
    {
        byte[] header = new byte[8];
        while (stream.Position < stream.Length)
        {
            long start = stream.Position;
            stream.ReadExactly(header);
            uint length = BinaryPrimitives.ReadUInt32BigEndian(header);
            if (length > int.MaxValue || length > stream.Length - stream.Position - 4)
                throw new ImageException("unreadableError");
            string type = Encoding.ASCII.GetString(header, 4, 4);
            yield return new Chunk(start, (int)length, type);
            stream.Position = start + 12 + length;
            if (type == "IEND")
                yield break;
        }
    }
    private static uint Crc(byte[] data, string type = "eXIf")
    {
        uint crc = uint.MaxValue;
        foreach (byte value in Encoding.ASCII.GetBytes(type).Concat(data))
        {
            crc ^= value;
            for (int i = 0; i < 8; i++)
                crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xEDB88320u : 0);
        }
        return ~crc;
    }
    private static void WriteChunk(Stream output, string type, byte[] data)
    {
        byte[] header = new byte[8];
        BinaryPrimitives.WriteUInt32BigEndian(header, (uint)data.Length);
        Encoding.ASCII.GetBytes(type).CopyTo(header, 4);
        output.Write(header);
        output.Write(data);
        byte[] crc = new byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(crc, Crc(data, type));
        output.Write(crc);
    }
    internal static void Replace(string path, byte[]? data, int? width = null, int? height = null)
    {
        string temporary = path + ".metadata";
        try
        {
            using (var input = File.OpenRead(path))
            using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write))
            {
                output.Write(Signature);
                input.Position = 8;
                byte[] buffer = new byte[65536];
                foreach (var chunk in Chunks(input))
                {
                    if (chunk.Type == "eXIf")
                        continue;
                    if (chunk.Type == "iTXt" && width is not null && height is not null)
                    {
                        if (chunk.Length > 16 * 1024 * 1024)
                            throw new ImageException("unsupportedError");
                        byte[] text = new byte[chunk.Length];
                        input.ReadExactly(text);
                        int keyword = Array.IndexOf(text, (byte)0);
                        if (keyword >= 0 && Encoding.ASCII.GetString(text, 0, keyword) == "XML:com.adobe.xmp")
                        {
                            int start = keyword + 3;
                            if (start >= text.Length || text[keyword + 1] > 1 || text[keyword + 2] != 0)
                                throw new ImageException("unreadableError");
                            start = Array.IndexOf(text, (byte)0, start) + 1;
                            if (start <= 0 || start >= text.Length)
                                throw new ImageException("unreadableError");
                            start = Array.IndexOf(text, (byte)0, start) + 1;
                            if (start <= 0 || start >= text.Length)
                                throw new ImageException("unreadableError");
                            string xml;
                            using (var content = new MemoryStream(text, start, text.Length - start))
                            using (var decoded = text[keyword + 1] == 1 ? (Stream)new ZLibStream(content, CompressionMode.Decompress) : content)
                            using (var reader = new StreamReader(decoded, Encoding.UTF8))
                            {
                                var builder = new StringBuilder();
                                char[] characters = new char[4096];
                                int count;
                                while ((count = reader.Read(characters, 0, characters.Length)) != 0)
                                {
                                    if (builder.Length + count > 16 * 1024 * 1024)
                                        throw new ImageException("unsupportedError");
                                    builder.Append(characters, 0, count);
                                }
                                xml = builder.ToString();
                            }
                            byte[] updated = Encoding.UTF8.GetBytes(XmpFraming.Normalize(xml, width.Value, height.Value));
                            byte[] payload = new byte[start + updated.Length];
                            text.AsSpan(0, start).CopyTo(payload);
                            payload[keyword + 1] = 0;
                            updated.CopyTo(payload, start);
                            WriteChunk(output, "iTXt", payload);
                            continue;
                        }
                    }
                    if (chunk.Type == "IEND" && data is not null)
                    {
                        WriteChunk(output, "eXIf", data);
                    }
                    input.Position = chunk.Start;
                    int remaining = checked(chunk.Length + 12);
                    while (remaining > 0)
                    {
                        int count = input.Read(buffer, 0, Math.Min(remaining, buffer.Length));
                        if (count == 0)
                            throw new EndOfStreamException();
                        output.Write(buffer, 0, count);
                        remaining -= count;
                    }
                }
                output.Flush(true);
            }
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
