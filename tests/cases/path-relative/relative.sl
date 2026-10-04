// SPDX-License-Identifier: 0BSD
//
// One path as reached from a directory, which is how a form file names a
// picture beside it.
module Relative;

import Standard.Console;
import Standard.Path;
import Standard.Text;

void Say(String what, String from, String to)
{
    // One separator for every platform, so one expected output does.
    String separator = Text.FromChar((char32)Standard.Path.DirectorySeparatorChar);
    Console.WriteLine(what + ": " + Standard.Path.GetRelativePath(from, to).Replace(separator, "/"));
}

int Main()
{
    Say("below", "src/forms", "src/forms/art/logo.png");
    Say("beside", "src/forms", "src/art/logo.png");
    Say("same", "src/forms", "src/forms");
    Say("above", "src/forms/deep", "src");
    Say("trailing separator", "src/forms/", "src/forms/a.png");
    Say("nothing shared", "one/two", "three");
    Say("absolute", "/srv/app", "/srv/art/a.png");
    Say("no common root", "relative/dir", "/absolute/a.png");
#if WINDOWS
    Say("another drive", "C:\\src", "D:\\art\\a.png");
    Say("one drive, either case", "C:\\src\\forms", "c:\\src\\art\\a.png");
#else
    Say("another drive", "C:\\src", "D:\\art\\a.png");
    Say("one drive, either case", "/src/forms", "/src/art/a.png");
#endif
    return 0;
}
