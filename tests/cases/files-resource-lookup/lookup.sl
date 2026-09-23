// SPDX-License-Identifier: 0BSD
//
// Lookups that the two routes to a resource have to answer alike: a name in
// any case, an empty resource, and a bitmap whose pixels do not follow its
// header directly.
module ResourceLookup;

import Standard.Console;
import Standard.Resources;

uint ReadU32(byte[] data, nuint at)
{
    return (uint)data[at]
         | ((uint)data[at + 1u] << 8)
         | ((uint)data[at + 2u] << 16)
         | ((uint)data[at + 3u] << 24);
}

void DescribeBitmap(String what, int id)
{
    var file = Resources.GetBitmapFile(id);
    if (file.Length < 14u)
    {
        Console.WriteLine($"{what}: missing");
        return;
    }
    Console.WriteLine($"{what}: {file.Length} bytes, pixels at {ReadU32(file, 10u)}");
}

int Main()
{
    Console.WriteLine($"as filed {Resources.Exists("TEXTBLOB", "GREETING")}");
    Console.WriteLine($"as written {Resources.Exists("TextBlob", "greeting")}");
    Console.WriteLine($"lower {Resources.GetBytes("textblob", "greeting").Length} bytes");
    Console.WriteLine($"other name {Resources.Exists("TextBlob", "farewell")}");

    Console.WriteLine($"empty exists {Resources.Exists(ResourceType.RcData, 302)}");
    Console.WriteLine($"empty size {Resources.GetSize(ResourceType.RcData, 302)}");

    DescribeBitmap("bitfields", 401);
    DescribeBitmap("core", 402);
    return 0;
}
