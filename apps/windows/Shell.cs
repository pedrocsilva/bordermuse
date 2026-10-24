using System.Runtime.InteropServices;

namespace BorderMuse.Windows;

internal static class Shell
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr CommandLineToArgvW(string commandLine, out int count);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr ILCreateFromPathW(string path);
    [DllImport("shell32.dll")] private static extern IntPtr ILFindLastID(IntPtr pidl);
    [DllImport("shell32.dll")] private static extern int SHOpenFolderAndSelectItems(IntPtr folder, uint count, IntPtr[] children, uint flags);
    public static IEnumerable<string> Arguments(string commandLine)
    {
        IntPtr memory = CommandLineToArgvW(commandLine, out int count);
        if (memory == IntPtr.Zero)
            return [];
        try
        {
            return Enumerable.Range(0, count).Select(i => Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory, i * IntPtr.Size))!).ToArray();
        }
        finally { LocalFree(memory); }
    }
    public static void Reveal(IReadOnlyList<string> files)
    {
        if (files.Count == 0)
            return;
        IntPtr folder = ILCreateFromPathW(Path.GetDirectoryName(files[0])!);
        var full = files.Select(ILCreateFromPathW).ToArray();
        try
        {
            Marshal.ThrowExceptionForHR(SHOpenFolderAndSelectItems(folder, (uint)full.Length, full.Select(ILFindLastID).ToArray(), 0));
        }
        finally { Marshal.FreeCoTaskMem(folder); foreach (var item in full) Marshal.FreeCoTaskMem(item); }
    }
}
