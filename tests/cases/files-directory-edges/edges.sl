// SPDX-License-Identifier: 0BSD
//
// Directory calls at the edges of what a path can say: nothing at all, which
// is the current directory, and a trailing separator, which names the same
// directory as the path without one.
module DirectoryEdges;

import Standard.Collections;
import Standard.Console;
import Standard.Directory;
import Standard.Env;
import Standard.File;
import Standard.IO;
import Standard.Path;

String Scratch()
{
    var temp = Env.GetVariableOrDefault("TEMP", Env.GetVariableOrDefault("TMPDIR", "/tmp"));
    return Path.Join(temp, "stainless-files-directory-edges");
}

String Slash() => Path.Separator == '/' ? "/" : "\\";

int Main()
{
    var root = Scratch();
    var deep = Path.Join(root, "x", "y");
    var file = Path.Join(root, "a.txt");

    File.Delete(file);
    Directory.Delete(deep);
    Directory.Delete(Path.Join(root, "x"));
    Directory.Delete(root);

    // Every parent made, and the trailing separator is the same directory.
    Console.WriteLine($"create all: {IO.DescribeIOError(Directory.CreateDirectoryTree(deep + Slash()))}");
    Console.WriteLine($"made: {Directory.Exists(deep)}");
    Console.WriteLine($"again: {IO.DescribeIOError(Directory.CreateDirectoryTree(deep + Slash()))}");
    File.WriteAllText(file, "a");

    // A directory is not a file, and deleting it as one is refused on both
    // platforms rather than on one.
    var empty = Path.Join(root, "x", "y");
    Console.WriteLine($"file delete of a directory failed: {File.Delete(empty) != IOError.None}");
    Console.WriteLine($"still there: {Directory.Exists(empty)}");

    // The listed path is spelled with the separator it was given once.
    var listed = Directory.GetFiles(root + Slash());
    if (listed.Ok)
        Console.WriteLine($"trailing separator: {listed.Value.Count} {listed.Value[0u] == file}");

    // The empty path is the current directory, and its entries are relative.
    var back = Env.CurrentDirectory();
    Env.SetCurrentDirectory(root);
    var here = Directory.GetFiles("");
    if (here.Ok)
    {
        Console.WriteLine($"current: {here.Value.Count} '{here.Value[0u]}'");
    }
    else
    {
        Console.WriteLine($"current failed: {IO.DescribeIOError(here.Error)}");
    }
    Env.SetCurrentDirectory(back);

    File.Delete(file);
    Directory.Delete(deep);
    Directory.Delete(Path.Join(root, "x"));
    Directory.Delete(root);
    Console.WriteLine($"cleaned: {!Directory.Exists(root)}");
    return 0;
}
