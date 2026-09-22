// SPDX-License-Identifier: 0BSD
//
// What a program carries inside itself.
//
//   stainless run samples/win32/resources.sl samples/win32/resources.rc \
//       bindings/win32 -l user32
//
// The `.rc` on that command line is the whole of the build step. It is
// compiled with `llvm-rc` -- which ships beside the clang already driving the
// build -- and the linker folds the result into the executable, so everything
// this program prints comes out of its own image. Move the binary somewhere
// else with nothing beside it and it still prints all of this.
//
// **This is a Windows idea.** A PE has a resource directory indexed by type and
// name that the loader itself reads; ELF has nothing equivalent, and a build
// for a non-Windows target leaves the script out and says so (SL0700). See
// `bindings/win32/Resources.sl` for where the line falls and why.
module ResourceSample;

import Standard.Console;
import Standard.Convert;
import Win32;
import Win32.Resources;
import Win32.User32;
import Win32.Kernel32;

// The same numbers `resources.h` gives the resource compiler. Stainless has no
// `#include`, so the two lists are kept side by side rather than shared -- see
// the note in that header.
const int IdsTitle    = 201;
const int IdsSubtitle = 202;
const int IdsReady    = 203;
const int IdrBanner   = 301;

static readonly String Dim  = "\x1b[90m";
static readonly String Bold = "\x1b[1m";
static readonly String Off  = "\x1b[0m";

void PrintHeading(String text)
{
    Console.WriteLine("");
    Console.WriteLine(Bold + text + Off);
}

void PrintLine(String label, String value)
{
    Console.WriteLine("  " + Dim + label + Off + "  " + value);
}

int Main()
{
    Win32.Terminal.EnableAnsiEscapes();

    // ------------------------------------------------------------ strings
    //
    // A string table is addressed by a bare id rather than by a resource name,
    // because Windows stores strings in blocks of sixteen and `LoadStringW`
    // works out which block holds the one asked for.
    PrintHeading(Resources.LoadString((uint)IdsTitle));
    PrintLine("subtitle", Resources.LoadString((uint)IdsSubtitle));
    PrintLine("ready", Resources.LoadString((uint)IdsReady));

    // An id with nothing behind it is an empty string rather than an abort. A
    // resource that is not there is an ordinary answer.
    PrintLine("id 999", "'" + Resources.LoadString(999u) + "'");

    // -------------------------------------------------------------- bytes
    PrintHeading("Bytes");

    // Copied out, which is what anything outliving the call wants.
    var banner = Resources.ReadResourceBytes(Resources.MakeIntResource(IdrBanner), RtRcData());
    PrintLine("banner", $"{banner.Length} bytes");

    // The same resource without copying: a pointer into the mapped image,
    // read-only and valid as long as this program is running. Nothing to free
    // -- `LoadResource` returns memory that was already there and
    // `LockResource` is a cast, which is why `FreeResource` has done nothing
    // since Win32 and is not bound.
    uint size = 0u;
    byte* at = Resources.GetResourcePointer(Resources.MakeIntResource(IdrBanner), RtRcData(),
        &size);
    PrintLine("in place", $"{size} bytes at a borrowed pointer: {at != null}");

    // A string name, and a type this program invented. Both halves of a
    // resource's identity may be either a number or a name.
    var licence = Resources.ReadResourceBytes("LICENCE".ToUtf16().ToPointer(),
                                  "TEXTBLOB".ToUtf16().ToPointer());
    PrintLine("licence", $"{licence.Length} bytes under a string name");

    // ------------------------------------------------------------ asking
    PrintHeading("What is actually in here");

    // Enumeration, which is how a program checks that its own build put in
    // what the script said rather than assuming. `#101` is the spelling a
    // resource script uses for an integer name, so what this prints can be
    // pasted straight back into the `.rc`.
    //
    // The string table shows up as one resource rather than three, and under a
    // name nothing here wrote: strings are filed in blocks of sixteen, so ids
    // 201 to 203 all live in block 13. That is why `LoadStringW` takes a bare
    // id and every other call takes a name.
    foreach (var type in Resources.GetResourceTypes())
    {
        var names = Resources.GetResourceNames(ParseTypeName(type));
        PrintLine(type, $"{names.Length} resource(s)");
        foreach (var name in names)
            Console.WriteLine("      " + Dim + name + Off);
    }

    PrintHeading("The manifest");

    // Nothing above asked for this one and it is here anyway: an RT_MANIFEST
    // is read by the loader before `Main` runs. It is what selects version 6
    // of comctl32, which is the difference between themed common controls and
    // the Windows 2000 look.
    char16* manifest = Resources.MakeIntResource(ManifestResourceId);
    PrintLine("RT_MANIFEST", $"{Resources.GetResourceSize(manifest, RtManifest())} bytes");

    // ----------------------------------------------------------- another
    PrintHeading("Another binary's resources");

    // `LOAD_LIBRARY_AS_DATAFILE` maps a file without running any code in it --
    // no DllMain, no imports resolved -- which is the only safe way to read
    // resources out of something this program did not build.
    var shell = Resources.OpenModuleForResources("C:\\Windows\\System32\\shell32.dll");
    if (shell == null)
    {
        PrintLine("shell32.dll", "could not be opened: " + Win32.GetLastErrorMessage());
    }
    else
    {
        String[] icons = Resources.GetResourceNamesIn(shell, RtGroupIcon());
        PrintLine("shell32.dll", $"{icons.Length} icon groups");
        Resources.CloseModule(shell);
    }

    Console.WriteLine("");
    return 0;
}

/// Turns what `GetResourceTypes()` printed back into the name an API wants.
///
/// `GetResourceTypes()` renders an integer type as `#10`, because that is how
/// a resource script spells one; this is the other direction, so that
/// enumerating types and then enumerating each type's names works without the
/// caller keeping the raw pointers around.
char16* ParseTypeName(String type)
{
    if (type.StartsWith("#"))
    {
        var number = Convert.ToInt(type.Substring(1u));
        if (number.Ok)
            return Resources.MakeIntResource(number.Value);
    }
    return type.ToUtf16().ToPointer();
}
