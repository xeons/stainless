// Two spellings of one file, which a platform creates without anybody choosing
// to: a compiler that joins a directory to a file name writes one separator
// from each half, and a debugger then has to decide whether that is the file
// the editor has open.
module Same;

import Standard.Console;
import Standard.Path;

void Say(String what, bool answer)
{
    Console.WriteLine(what + ": " + (answer ? "same" : "different"));
}

int Main()
{
    // Mixed separators, which is what the compiler's own debug information
    // contains on Windows and is an ordinary filename character on Linux.
    Say("mixed separators",
        Standard.Path.SamePath("src\\obj/Text.sl", "src\\obj\\Text.sl"));

    // Case, which Windows ignores and Linux does not.
    Say("case", Standard.Path.SamePath("src/Text.sl", "src/text.sl"));

    // Neither platform says these are one file.
    Say("different names", Standard.Path.SamePath("src/Text.sl", "src/Json.sl"));
    Say("different lengths", Standard.Path.SamePath("src/Text.sl", "src/Text.slx"));

    // Nothing is resolved, so a relative path is not the absolute one it would
    // reach. Said out loud here, because the doc comment is the only other
    // place it is written down.
    Say("unresolved", Standard.Path.SamePath("a/../b/Text.sl", "b/Text.sl"));
    return 0;
}
