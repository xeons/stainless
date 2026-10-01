// SPDX-License-Identifier: 0BSD
//
// Resources and embeds in a Mach-O object.
//
// Mach-O names a section `__SEGMENT,__section`, and its permissions are the
// segment's. The resource blob goes in a section of its own in `__DATA_CONST`,
// and each embed in a section of the segment with its access, or in the one
// named here.
module MachOSections;

import Standard.Console;
import Standard.Resources;

public static class Blobs
{
    /// Read-only: `__DATA_CONST,__const`.
    [Embed("table.bin")]
    public static readonly byte[] Table;

    /// Writable: `__DATA,__data`.
    [Embed("table.bin", Access = "rw")]
    public static byte[] Scratch;

    /// `mov w0, #42; ret`, in `__TEXT,__text`.
    [Embed("stub.bin", Access = "rx")]
    public static readonly byte[] Stub;

    /// A section of its own in a segment with the access asked for.
    [Embed("table.bin", Section = "__DATA,__sl_table", Access = "rw")]
    public static byte[] Named;

    [Embed("stub.bin", Section = "__TEXT,__sl_stub", Access = "rx")]
    public static readonly byte[] NamedStub;
}

int Main()
{
    Console.WriteLine(Resources.GetText(201u));
    Console.WriteLine($"{Blobs.Table.Length} {Blobs.Scratch.Length} {Blobs.Stub.Length}");
    Console.WriteLine($"{Blobs.Named.Length} {Blobs.NamedStub.Length}");
    return 0;
}
