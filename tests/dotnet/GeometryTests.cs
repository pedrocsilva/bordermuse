using System.Text.Json;
using BorderMuse.Core;
using BorderMuse.Geometry;
using Xunit;

namespace BorderMuse.Tests;

public sealed class GeometryTests
{
    [Fact]
    public void AllMeasuredCasesMatchEveryMargin()
    {
        using var corpus = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "conformance-v1.json")));
        Assert.Equal(CanvasLayout.ContractId, corpus.RootElement.GetProperty("spec_id").GetString());
        var cases = corpus.RootElement.GetProperty("cases");
        Assert.Equal(20, cases.GetArrayLength());
        foreach (var test in cases.EnumerateArray())
        {
            var input = test.GetProperty("input");
            var ratio = input.GetProperty("ratio");
            var actual = CanvasLayout.Calculate(new PixelSize(input.GetProperty("width").GetInt64(), input.GetProperty("height").GetInt64()),
                input.GetProperty("thickness").GetInt32(), new AspectRatio(ratio[0].GetInt64(), ratio[1].GetInt64()));
            var expected = test.GetProperty("expected");
            Assert.Equal(new CanvasLayout(expected.GetProperty("width").GetInt64(), expected.GetProperty("height").GetInt64(),
                expected.GetProperty("left").GetInt64(), expected.GetProperty("right").GetInt64(),
                expected.GetProperty("top").GetInt64(), expected.GetProperty("bottom").GetInt64()), actual);
        }
    }
    [Fact]
    public void ExactBoundariesOddSizesAndOriginal()
    {
        Assert.Equal(new CanvasLayout(114, 114, 7, 7, 7, 7), CanvasLayout.Calculate(new PixelSize(100, 100), 14));
        var odd = new PixelSize(1201, 799);
        Assert.Equal(CanvasLayout.Calculate(odd, 7), CanvasLayout.Calculate(odd, 7, new AspectRatio(1201, 799)));
        Assert.Equal(new CanvasLayout(107, 85, 3, 3, 9, 9), CanvasLayout.Calculate(new PixelSize(101, 67), 7, new AspectRatio(5, 4)));
        Assert.Equal(new PixelSize(400, 600), new BorderSettings { ReduceSize = true, LongEdge = 600 }.PreparedSize(new PixelSize(801, 1201)));
        Assert.Equal(new PixelSize(801, 1201), new BorderSettings { ReduceSize = true, LongEdge = 3000 }.PreparedSize(new PixelSize(801, 1201)));
    }
    [Fact]
    public void InvalidDefaultValuesAndOverflowFail()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new PixelSize(0, 10));
        Assert.Throws<ArgumentOutOfRangeException>(() => CanvasLayout.Calculate(default, 10));
        Assert.Throws<ArgumentOutOfRangeException>(() => CanvasLayout.Calculate(new PixelSize(1, 1), 10, default(AspectRatio)));
        Assert.Throws<ArgumentOutOfRangeException>(() => CanvasLayout.Calculate(new PixelSize(1, 1), 51));
        Assert.Throws<FormatException>(() => AspectRatio.Parse("1:2:3"));
        Assert.Throws<ArgumentOutOfRangeException>(() => AspectRatio.Parse("0:1"));
        Assert.Throws<OverflowException>(() => CanvasLayout.Calculate(new PixelSize(long.MaxValue, 100), 50, new AspectRatio(1, 1)));
    }
}
