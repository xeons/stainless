// `#pragma comment(lib, "...")`: the file names the library it needs.
//
// This case links user32 and gdi32 and passes **no `-l`** — there is no
// libraries.txt beside it, which is the whole point. The names come from the
// pragmas below and nowhere else.
//
// It is MSVC's spelling because that is the one every Windows header already
// uses, and both `"user32"` and `"gdi32.lib"` are accepted: the linker wants
// the first form, and the second is what a C programmer will type.
module PragmaLibrary;

import Standard.Console;

#pragma comment(lib, "user32")
#pragma comment(lib, "gdi32.lib")

// Naming one twice is not an error; it is linked once.
#pragma comment(lib, "user32")

// A pragma inside a branch that is not taken means nothing, exactly as a
// declaration there would.
#if LINUX
#pragma comment(lib, "this-library-does-not-exist")
#endif

extern "C" {
    int   GetSystemMetrics(int index);          // user32
    void* CreateSolidBrush(uint colour);        // gdi32
    int   DeleteObject(void* object);           // gdi32
}

int Main() {
    // Both libraries resolved, so both calls are real.
    Console.WriteLine("screen is wider than nothing: "
        + Text.FromBool(GetSystemMetrics(0) > 0));

    void* brush = CreateSolidBrush(0x00FF00u);
    Console.WriteLine("a brush was made: " + Text.FromBool(brush != null));
    Console.WriteLine("and deleted: " + Text.FromBool(DeleteObject(brush) != 0));
    return 0;
}
