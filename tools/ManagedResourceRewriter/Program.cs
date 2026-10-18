using System.ComponentModel;
using System.Runtime.InteropServices;
using Mono.Cecil;

internal static class Program
{
    private const int RtIcon = 3;
    private const int RtGroupIcon = 14;
    private const ushort NeutralLanguage = 0;

    public static int Main(string[] args)
    {
        if (args.Length < 4)
        {
            PrintUsage();
            return 2;
        }

        var inputPath = Path.GetFullPath(args[0]);
        var outputPath = Path.GetFullPath(args[1]);
        string? iconPath = null;
        var argIndex = 2;

        if (argIndex < args.Length && string.Equals(args[argIndex], "--icon", StringComparison.OrdinalIgnoreCase))
        {
            if (argIndex + 1 >= args.Length)
            {
                PrintUsage();
                return 2;
            }

            iconPath = Path.GetFullPath(args[argIndex + 1]);
            argIndex += 2;
        }

        if ((args.Length - argIndex) < 2 || (args.Length - argIndex) % 2 != 0)
        {
            PrintUsage();
            return 2;
        }

        if (!File.Exists(inputPath))
        {
            Console.Error.WriteLine($"Input assembly not found: {inputPath}");
            return 3;
        }

        if (iconPath is not null && !File.Exists(iconPath))
        {
            Console.Error.WriteLine($"Icon file not found: {iconPath}");
            return 4;
        }

        var replacements = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        for (var i = argIndex; i < args.Length; i += 2)
        {
            var resourceName = args[i];
            var replacementFile = Path.GetFullPath(args[i + 1]);
            if (!File.Exists(replacementFile))
            {
                Console.Error.WriteLine($"Replacement file not found: {replacementFile}");
                return 5;
            }

            replacements[resourceName] = File.ReadAllBytes(replacementFile);
        }

        try
        {
            RewriteManagedResources(inputPath, outputPath, replacements);

            if (iconPath is not null)
            {
                ApplyIconResource(outputPath, iconPath);
                Console.WriteLine($"Applied icon {iconPath}");
            }

            Console.WriteLine($"Written {outputPath}");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 6;
        }
    }

    private static void PrintUsage()
    {
        Console.Error.WriteLine("Usage: ManagedResourceRewriter <input-exe> <output-exe> [--icon <ico-file>] <resource-name> <replacement-file> [<resource-name> <replacement-file> ...]");
    }

    private static void RewriteManagedResources(string inputPath, string outputPath, Dictionary<string, byte[]> replacements)
    {
        var readerParameters = new ReaderParameters
        {
            ReadWrite = false,
            InMemory = true
        };

        using var module = ModuleDefinition.ReadModule(inputPath, readerParameters);

        foreach (var (resourceName, bytes) in replacements)
        {
            var index = module.Resources.ToList().FindIndex(resource => resource.Name == resourceName);
            if (index < 0)
            {
                module.Resources.Add(new EmbeddedResource(resourceName, ManifestResourceAttributes.Private, bytes));
                Console.WriteLine($"Added {resourceName}: {bytes.Length} bytes");
                continue;
            }

            var current = module.Resources[index];
            var attributes = current.Attributes;
            module.Resources.RemoveAt(index);
            module.Resources.Insert(index, new EmbeddedResource(resourceName, attributes, bytes));
            Console.WriteLine($"Replaced {resourceName}: {bytes.Length} bytes");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        module.Write(outputPath, new WriterParameters());
    }

    private static void ApplyIconResource(string exePath, string iconPath)
    {
        var icon = ReadIconFile(iconPath);
        var updateHandle = NativeMethods.BeginUpdateResource(exePath, false);
        if (updateHandle == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "BeginUpdateResource failed");
        }

        var discard = true;
        try
        {
            for (var i = 0; i < icon.Entries.Length; i++)
            {
                var id = (ushort)(i + 1);
                icon.Entries[i] = icon.Entries[i] with { Id = id };

                if (!NativeMethods.UpdateResource(updateHandle, (IntPtr)RtIcon, (IntPtr)id, NeutralLanguage, icon.Images[i], icon.Images[i].Length))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), $"UpdateResource RT_ICON {id} failed");
                }
            }

            var groupData = BuildGroupIconResource(icon.Entries);
            foreach (var groupId in new ushort[] { 1, 32512 })
            {
                if (!NativeMethods.UpdateResource(updateHandle, (IntPtr)RtGroupIcon, (IntPtr)groupId, NeutralLanguage, groupData, groupData.Length))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), $"UpdateResource RT_GROUP_ICON {groupId} failed");
                }
            }

            discard = false;
        }
        finally
        {
            if (!NativeMethods.EndUpdateResource(updateHandle, discard) && !discard)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "EndUpdateResource failed");
            }
        }
    }

    private static IconFile ReadIconFile(string iconPath)
    {
        var bytes = File.ReadAllBytes(iconPath);
        if (bytes.Length < 6)
        {
            throw new InvalidDataException("Invalid ICO file.");
        }

        var reserved = ReadUInt16(bytes, 0);
        var type = ReadUInt16(bytes, 2);
        var count = ReadUInt16(bytes, 4);
        if (reserved != 0 || type != 1 || count == 0)
        {
            throw new InvalidDataException("Invalid ICO header.");
        }

        var entries = new IconEntry[count];
        var images = new byte[count][];
        var offset = 6;

        for (var i = 0; i < count; i++)
        {
            if (offset + 16 > bytes.Length)
            {
                throw new InvalidDataException("Invalid ICO directory.");
            }

            var width = bytes[offset];
            var height = bytes[offset + 1];
            var colorCount = bytes[offset + 2];
            var reservedByte = bytes[offset + 3];
            var planes = ReadUInt16(bytes, offset + 4);
            var bitCount = ReadUInt16(bytes, offset + 6);
            var imageSize = ReadUInt32(bytes, offset + 8);
            var imageOffset = ReadUInt32(bytes, offset + 12);

            if (imageOffset > bytes.Length || imageSize > bytes.Length - imageOffset)
            {
                throw new InvalidDataException("Invalid ICO image data.");
            }

            entries[i] = new IconEntry(width, height, colorCount, reservedByte, planes, bitCount, imageSize, 0);
            images[i] = bytes.AsSpan((int)imageOffset, (int)imageSize).ToArray();
            offset += 16;
        }

        return new IconFile(entries, images);
    }

    private static byte[] BuildGroupIconResource(IconEntry[] entries)
    {
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream);
        writer.Write((ushort)0);
        writer.Write((ushort)1);
        writer.Write((ushort)entries.Length);

        foreach (var entry in entries)
        {
            writer.Write(entry.Width);
            writer.Write(entry.Height);
            writer.Write(entry.ColorCount);
            writer.Write(entry.Reserved);
            writer.Write(entry.Planes);
            writer.Write(entry.BitCount);
            writer.Write(entry.BytesInResource);
            writer.Write(entry.Id);
        }

        writer.Flush();
        return stream.ToArray();
    }

    private static ushort ReadUInt16(byte[] bytes, int offset)
    {
        return BitConverter.ToUInt16(bytes, offset);
    }

    private static uint ReadUInt32(byte[] bytes, int offset)
    {
        return BitConverter.ToUInt32(bytes, offset);
    }

    private sealed record IconFile(IconEntry[] Entries, byte[][] Images);

    private readonly record struct IconEntry(
        byte Width,
        byte Height,
        byte ColorCount,
        byte Reserved,
        ushort Planes,
        ushort BitCount,
        uint BytesInResource,
        ushort Id);

    private static class NativeMethods
    {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        internal static extern IntPtr BeginUpdateResource(string fileName, [MarshalAs(UnmanagedType.Bool)] bool deleteExistingResources);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool UpdateResource(IntPtr updateHandle, IntPtr type, IntPtr name, ushort language, byte[] data, int dataSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EndUpdateResource(IntPtr updateHandle, [MarshalAs(UnmanagedType.Bool)] bool discard);
    }
}
