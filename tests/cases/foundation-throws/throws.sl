// SPDX-License-Identifier: 0BSD
//
// The generated Foundation bindings mark NSFileHandle's reads and seeks
// [Throws]: a read that works answers its bytes, and a seek on a pipe raises
// NSFileHandleOperationException, which comes back as a value.
module FoundationThrows;

import Standard.Console;
import Standard.Text;
import MacOS.Foundation;

int Main()
{
    var opened = NSFileHandle.FileHandleForReadingAtPath(NSString.StringWithUTF8String("/etc/hosts".ToPointer())!);
    if (opened == null)
    {
        Console.WriteLine("/etc/hosts would not open");
        return 1;
    }
    var file = (NSFileHandle)opened;
    var read = file.ReadDataOfLength(4u);
    Console.WriteLine("read: " + (read.Ok ? FromInteger((int)read.Value.Length) + " bytes" : read.Error.Name));
    var closed = file.CloseFile();
    Console.WriteLine("closed: " + (closed == null ? "fine" : ((ForeignException)closed).Name));

    var pipe = NSPipe.Pipe();
    var sought = pipe.FileHandleForReading.SeekToFileOffset(10u);
    Console.WriteLine("seek a pipe: " + (sought == null ? "fine" : ((ForeignException)sought).Name));
    return 0;
}
