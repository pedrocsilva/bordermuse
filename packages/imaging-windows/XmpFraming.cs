using System.Globalization;
using System.Xml.Linq;

namespace BorderMuse.Imaging.Windows;

internal static class XmpFraming
{
    internal static string Normalize(string xml, int width, int height)
    {
        var document = XDocument.Parse(xml, LoadOptions.PreserveWhitespace);
        XNamespace tiff = "http://ns.adobe.com/tiff/1.0/", exif = "http://ns.adobe.com/exif/1.0/", xmp = "http://ns.adobe.com/xap/1.0/";
        var values = new Dictionary<XName, int> { [tiff + "Orientation"] = 1, [tiff + "ImageWidth"] = width, [tiff + "ImageLength"] = height, [exif + "PixelXDimension"] = width, [exif + "PixelYDimension"] = height };
        foreach (var element in document.Descendants().ToArray())
        {
            if (values.TryGetValue(element.Name, out int value))
                element.Value = value.ToString(CultureInfo.InvariantCulture);
            foreach (var attribute in element.Attributes())
                if (values.TryGetValue(attribute.Name, out value))
                    attribute.Value = value.ToString(CultureInfo.InvariantCulture);
            if (element.Name == xmp + "Thumbnails")
                element.Remove();
        }
        return document.ToString(SaveOptions.DisableFormatting);
    }
}
