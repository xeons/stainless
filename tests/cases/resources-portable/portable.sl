// SPDX-License-Identifier: 0BSD
//
// Resources, read identically on every target.
//
// There is no `#if` in this program and there is not meant to be. On Windows
// `Standard.Resources` asks `FindResourceW` and walks the PE's own resource
// directory; everywhere else it walks the compiled `.res` the compiler put in
// the binary's `.rsrc` section. The point of the case is that the two answer
// the same, so the expected output is shared rather than per-platform.
module PortableResources;

import Standard.Console;
import Standard.Resources;

int Main()
{
    // A string table is the kind that needs real interpretation rather than a
    // lookup: strings are filed sixteen to a block, so 201 is the tenth entry
    // of block 13 and 218 is the third entry of block 14. Windows does that
    // arithmetic inside LoadStringW; off Windows it is done by hand, and the
    // two have to agree.
    Console.WriteLine(Resources.GetText(201u));
    Console.WriteLine(Resources.GetText(202u));
    Console.WriteLine(Resources.GetText(218u));
    Console.WriteLine($"absent '{Resources.GetText(999u)}'");

    var payload = Resources.GetBytes(Resources.RcData, 301);
    Console.WriteLine($"payload {payload.Length} bytes, first {(char32)payload[0u]}");

    uint borrowed = 0u;
    byte* at = Resources.GetPointer(Resources.RcData, 301, &borrowed);
    Console.WriteLine($"in place {borrowed} bytes, pointer {at != null}");

    var greeting = Resources.GetBytes("TEXTBLOB", "GREETING");
    Console.WriteLine($"greeting {greeting.Length} bytes");

    Console.WriteLine($"present {Resources.Exists(Resources.RcData, 301)}");
    Console.WriteLine($"absent {Resources.Exists(Resources.RcData, 999)}");
    Console.WriteLine($"size {Resources.GetSize(Resources.RcData, 301)}");
    return 0;
}
