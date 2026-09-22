// SPDX-License-Identifier: 0BSD
//
// Where a path's text meets its edges: a drive's root, a trailing dot, and a
// separator that is not the platform's own.
module PathEdges;

import Standard.Console;
import Standard.Path;

void Say(String what, String answer)
{
    Console.WriteLine($"{what}: '{answer}'");
}

int Main()
{
    // The root is kept rather than dropped, which would name somewhere else:
    // `C:` on its own is that drive's current directory.
    Say("directory of /foo", Path.GetDirectoryName("/foo"));
    Say("directory of C:\\foo", Path.GetDirectoryName("C:\\foo"));
    Say("directory of C:/foo", Path.GetDirectoryName("C:/foo"));
    Say("directory of C:\\", Path.GetDirectoryName("C:\\"));
    Say("directory of C:\\a\\b", Path.GetDirectoryName("C:\\a\\b"));

    // A dot with nothing after it is not an extension.
    Say("extension of a.", Path.GetExtension("a."));
    Say("extension of a.b.", Path.GetExtension("a.b."));
    Say("without extension of a.", Path.GetFileNameWithoutExtension("a."));

    // Only the extension changes; the directory is left as written.
    Say("a/b.txt as md", Path.ChangeExtension("a/b.txt", "md"));
    Say("a/b as .md", Path.ChangeExtension("a/b", ".md"));
    Say("a/b.txt without", Path.ChangeExtension("a/b.txt", ""));
    Say("b.txt as md", Path.ChangeExtension("b.txt", "md"));
    return 0;
}
