// SPDX-License-Identifier: 0BSD
//
// Resources compiled into the binary and read back out of it.
//
// The whole point is that nothing here touches the filesystem: `resources.rc`
// is compiled by the build and folded into this executable, so every value
// below comes out of the running image. A program that printed these by
// reading a file beside itself would pass the same assertions and prove
// nothing, which is why there is no file beside it to read.
module ResourceCase;

import Standard.Console;
import Win32.Resources;
import Win32.User32;

int Main()
{
    // A string table, which is the one resource kind addressed by a bare id
    // rather than by a name -- Windows stores strings in blocks of sixteen and
    // works out which block holds the one asked for.
    Console.WriteLine(Resources.LoadString(201u));
    Console.WriteLine(Resources.LoadString(202u));

    // An id with nothing behind it is empty rather than an abort: a resource
    // that is not there is an ordinary answer, not a broken program.
    Console.WriteLine($"missing string: '{Resources.LoadString(999u)}'");

    // Arbitrary bytes. The count includes the NUL the script wrote, because a
    // resource is exactly as long as what went into it.
    var payload = Resources.ReadResourceBytes(Resources.MakeIntResource(301), RtRcData());
    Console.WriteLine($"payload: {payload.Length} bytes, first {(char32)payload[0u]}");

    // The same resource reached without copying. Same length, same bytes.
    uint size = 0u;
    byte* at = Resources.GetResourcePointer(Resources.MakeIntResource(301), RtRcData(), &size);
    Console.WriteLine($"in place: {size} bytes, borrowed {at != null}");

    // A string name and a custom type, which is the other shape a resource
    // name takes. `rc` upper-cases both.
    var blob = Resources.ReadResourceBytes("GREETING".ToUtf16().ToPointer(),
                               "TEXTBLOB".ToUtf16().ToPointer());
    Console.WriteLine($"greeting: {blob.Length} bytes");

    char16* id = Resources.MakeIntResource(301);
    Console.WriteLine($"payload present: {Resources.ResourceExists(id, RtRcData())}");
    Console.WriteLine($"icon present: {Resources.ResourceExists(id, RtGroupIcon())}");
    Console.WriteLine($"payload size: {Resources.GetResourceSize(id, RtRcData())}");

    // What the binary actually holds, which is how a program checks that its
    // own build put in what the script said. `#101` is the spelling a resource
    // script uses for an integer name, so what this prints can be pasted back.
    foreach (var type in Resources.GetResourceTypes())
        Console.WriteLine($"type {type}");
    foreach (var name in Resources.GetResourceNames(RtRcData()))
        Console.WriteLine($"rcdata {name}");

    // The version this binary reports, out of its own RT_VERSION. Read through
    // version.dll rather than the resource API, because a version resource is a
    // tree rather than a value -- and read from the *file*, since that is all
    // `GetFileVersionInfoW` offers, so `ReadProgramVersion()` finds its own path first.
    Console.WriteLine($"version {Resources.ReadProgramVersion().Text}");

    // MAKEINTRESOURCE both ways round.
    Console.WriteLine($"id 301 is an id: {Resources.IsIntResource(id)}");
    Console.WriteLine($"and reads back as {Resources.GetIntResourceId(id)}");
    Console.WriteLine($"named {Resources.FormatResourceName(id)}");

    return 0;
}
