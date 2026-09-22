// SPDX-License-Identifier: 0BSD
//
// A link to a directory is not a directory, on either platform. A walk that
// followed one pointing at its own ancestor went round until the path was too
// long to open.
module DirectoryLinks;

import Standard.Collections;
import Standard.Console;
import Standard.Directory;
import Standard.Env;
import Standard.File;
import Standard.IO;
import Standard.Path;
import Standard.Process;

String Scratch()
{
    var temp = Env.GetOr("TEMP", Env.GetOr("TMPDIR", "/tmp"));
    return Path.Join(temp, "stainless-files-directory-links");
}

bool LinkDirectory(String link, String target)
{
#if WINDOWS
    // A junction, because a directory symbolic link needs a privilege.
    var made = Process.Run("cmd", ["/c", "mklink", "/J", link, target]);
#else
    var made = Process.Run("ln", ["-s", target, link]);
#endif
    return made.Ok && made.Value.ExitCode == 0;
}

int Main()
{
    var root = Scratch();
    var sub = Path.Join(root, "sub");
    var loop = Path.Join(sub, "loop");
    var file = Path.Join(sub, "file.txt");

    File.Delete(loop);
    File.Delete(file);
    Directory.Delete(sub);
    Directory.Delete(root);

    Directory.CreateAll(sub);
    File.WriteAllText(file, "x");
    if (!LinkDirectory(loop, root))
    {
        Console.WriteLine("could not make a link");
        return 1;
    }

    var entries = Directory.Entries(sub);
    if (entries.Ok)
    {
        foreach (var entry in entries.Value)
        {
            if (entry.Name == "loop")
                Console.WriteLine($"loop is a directory: {entry.IsDirectory}");
        }
    }

    var all = Directory.AllFiles(root);
    if (all.Ok)
    {
        Console.WriteLine($"all files: {all.Value.Count}");
    }
    else
    {
        Console.WriteLine($"all files failed: {IO.Describe(all.Error)}");
    }

    // Deleted as the file it is reported as, and the target stays.
    Console.WriteLine($"delete link: {IO.Describe(File.Delete(loop))}");
    Console.WriteLine($"target still there: {Directory.Exists(root)}");

    File.Delete(file);
    Directory.Delete(sub);
    Directory.Delete(root);
    Console.WriteLine($"cleaned: {!Directory.Exists(root)}");
    return 0;
}
