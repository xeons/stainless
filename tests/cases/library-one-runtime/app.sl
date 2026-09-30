// SPDX-License-Identifier: 0BSD
//
// A program and the Stainless library it links MUST share one runtime: one
// allocator, one set of counts, one stdio buffer. The loader is asked how
// many copies it mapped, which is the question itself rather than a symptom
// of it.
module App;

import Standard.Console;
import Standard.Text;
import Library.Boxes;

// Defined in loaded.c.
extern "C" int runtimes_loaded();

// The box is made in the library and released as this returns.
int ReadLibraryBox()
{
    var box = Box.Make(7);
    return box.Value;
}

int Main()
{
    Console.WriteLine("before");
    Console.WriteLine("released here " + Text.FromInteger(ReadLibraryBox()));
    Console.WriteLine("runtimes " + Text.FromInteger(runtimes_loaded()));
    return 0;
}
