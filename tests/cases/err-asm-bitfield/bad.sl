// SPDX-License-Identifier: 0BSD
module Bad;

public struct Flags
{
    public uint Ready : 1;
    public uint Count : 7;
}

int Main()
{
    Flags flags;
    flags.Ready = 0;
    flags.Count = 0;
    asm (out eax = flags.Count) { mov eax, 3 }
    return (int)flags.Count;
}
