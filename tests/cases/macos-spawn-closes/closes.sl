// SPDX-License-Identifier: 0BSD
//
// A child receives its three streams and nothing else, even a descriptor this
// process opened without asking for close-on-exec. On macOS a child is started
// with posix_spawn and POSIX_SPAWN_CLOEXEC_DEFAULT, which is what makes that
// true; fork and exec would have handed the file over.
module MacSpawnCloses;

import Standard.Console;
import Standard.Process;

extern "C"
{
    int open(byte* path, int flags, ...);
    int close(int fd);
    int unlink(byte* path);
}

const int CreateAndWrite = 0x0201;      // O_WRONLY | O_CREAT

int Main()
{
    int kept = open("/tmp/stainless-spawn-marker", CreateAndWrite, 384);
    Console.WriteLine($"opened: {kept >= 0}");

    var listed = RunProcess("sh", ["-c", "/usr/sbin/lsof -p $$ 2>/dev/null | grep -c stainless-spawn-marker || true"]);
    if (listed.Ok)
        Console.WriteLine("the child holds it: " + listed.Value.StandardOutput.Trim());

    // And the check can see one: the shell opens the file itself here.
    var opened = RunProcess("sh", ["-c", "exec 7>/tmp/stainless-spawn-marker; /usr/sbin/lsof -p $$ 2>/dev/null | grep -c stainless-spawn-marker || true"]);
    if (opened.Ok)
        Console.WriteLine("a child that opens it holds it: " + opened.Value.StandardOutput.Trim());

    close(kept);
    unlink("/tmp/stainless-spawn-marker");
    return 0;
}
