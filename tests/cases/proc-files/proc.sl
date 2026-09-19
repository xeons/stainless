// A file that reports no size and then hands over kilobytes.
//
// `/proc` and `/sys` do exactly that, and a reader that trusts the size gets
// nothing back from either. This is the case that pins `ReadAllBytes` reading
// to the end rather than to the length -- without it a debugger cannot find
// where a program was loaded, which is how it was noticed.
module Proc;

import Standard.Console;
import Standard.File;
import Standard.Text;

int Main()
{
    bool read = false;
    bool sensible = false;

    var maps = Standard.File.ReadAllText("/proc/self/maps");
    if (maps.Ok)
    {
        String text = maps.Value;
        read = text.ByteLength() > 0u;

        // Every process has one of these, so this says the content is the
        // file's rather than whatever happened to be in the buffer.
        sensible = read && (text.Contains("[heap]") || text.Contains("[stack]"));
    }

    Console.WriteLine("maps has content: " + (read ? "true" : "false"));
    Console.WriteLine("maps mentions the heap or the stack: "
                      + (sensible ? "true" : "false"));

    // That an ordinary file still reads exactly is not checked here: every
    // other case in this directory reads one, so a regression there fails
    // three hundred tests rather than this one.
    return 0;
}
