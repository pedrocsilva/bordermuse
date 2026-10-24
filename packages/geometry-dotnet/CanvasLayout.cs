using System.Globalization;
using System.Numerics;

namespace BorderMuse.Geometry;

public readonly record struct PixelSize
{
    public long Width
    {
        get;
    }
    public long Height
    {
        get;
    }
    public PixelSize(long width, long height)
    {
        if (width <= 0 || height <= 0)
            throw new ArgumentOutOfRangeException(nameof(width));
        Width = width;
        Height = height;
    }
}

public readonly record struct AspectRatio
{
    public long Width
    {
        get;
    }
    public long Height
    {
        get;
    }
    public AspectRatio(long width, long height)
    {
        if (width <= 0 || height <= 0)
            throw new ArgumentOutOfRangeException(nameof(width));
        long a = width, b = height;
        while (b != 0)
            (a, b) = (b, a % b);
        Width = width / a;
        Height = height / a;
    }
    public static AspectRatio? Parse(string value)
    {
        if (value == "original")
            return null;
        var parts = value.Split(':');
        if (parts.Length != 2 ||
            !long.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out var w) ||
            !long.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var h))
            throw new FormatException("Invalid aspect ratio.");
        return new AspectRatio(w, h);
    }
}

/// <summary>Exact bordermuse-geometry-v1; no imaging or application dependencies.</summary>
public readonly record struct CanvasLayout(long Width, long Height, long Left, long Right, long Top, long Bottom)
{
    public const string ContractId = "bordermuse-geometry-v1";
    public static CanvasLayout Calculate(PixelSize content, int thickness, AspectRatio? ratio = null)
    {
        // Validate again because default(struct) can bypass constructors.
        if (content.Width <= 0 || content.Height <= 0)
            throw new ArgumentOutOfRangeException(nameof(content));
        if (thickness is < 0 or > 50)
            throw new ArgumentOutOfRangeException(nameof(thickness));
        var r = ratio ?? new AspectRatio(content.Width, content.Height);
        if (r.Width <= 0 || r.Height <= 0)
            throw new ArgumentOutOfRangeException(nameof(ratio));
        BigInteger w = content.Width, h = content.Height, rw = r.Width, rh = r.Height, mx, my;
        if (w * rh >= h * rw)
        {
            mx = w * thickness / 200;
            my = (w * (100 + thickness) * rh - 100 * h * rw) / (200 * rw);
        }
        else
        {
            mx = (h * (100 + thickness) * rw - 100 * w * rh) / (200 * rh);
            my = h * thickness / 200;
        }
        return new CanvasLayout(checked((long)(w + 2 * mx)), checked((long)(h + 2 * my)),
            checked((long)mx), checked((long)mx), checked((long)my), checked((long)my));
    }
}
