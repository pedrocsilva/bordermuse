using BorderMuse.Core;
using BorderMuse.Imaging.Windows;

try
{
    if (args.Length == 1 && args[0] == "--help")
    {
        Console.WriteLine(Strings.Text("cliHelp"));
        return 0;
    }
    var options = new Dictionary<string, string>();
    for (int i = 0; i < args.Length; i += 2)
    {
        if (i + 1 >= args.Length || args[i] is not ("--input" or "--output" or "--border-percent" or "--aspect-ratio") || !options.TryAdd(args[i], args[i + 1]))
            throw new ArgumentException();
    }
    if (options.Count != 4 || !int.TryParse(options["--border-percent"], out int thickness))
        throw new ArgumentException();
    var settings = new BorderSettings { Thickness = thickness, Ratio = options["--aspect-ratio"] };
    settings.Validate();
    var processor = new ImageProcessor();
    var info = processor.Inspect(options["--input"]);
    processor.Export(options["--input"], options["--output"], settings, info.Version, default);
    return 0;
}
catch (ArgumentException) { Console.Error.WriteLine(Strings.Text("cliHelp")); return 2; }
catch (Exception error) { Console.Error.WriteLine(Strings.Message(error)); return 1; }
