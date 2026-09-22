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
    Say("directory of /foo", Path.DirectoryName("/foo"));
    Say("directory of C:\\foo", Path.DirectoryName("C:\\foo"));
    Say("directory of C:/foo", Path.DirectoryName("C:/foo"));
    Say("directory of C:\\", Path.DirectoryName("C:\\"));
    Say("directory of C:\\a\\b", Path.DirectoryName("C:\\a\\b"));

    // A dot with nothing after it is not an extension.
    Say("extension of a.", Path.Extension("a."));
    Say("extension of a.b.", Path.Extension("a.b."));
    Say("without extension of a.", Path.WithoutExtension("a."));

    // Only the extension changes; the directory is left as written.
    Say("a/b.txt as md", Path.WithExtension("a/b.txt", "md"));
    Say("a/b as .md", Path.WithExtension("a/b", ".md"));
    Say("a/b.txt without", Path.WithExtension("a/b.txt", ""));
    Say("b.txt as md", Path.WithExtension("b.txt", "md"));
    return 0;
}
