// SPDX-License-Identifier: 0BSD
//
// The object header is three words, twelve bytes here, so a field that wants
// eight has to be aligned by where it sits in the object and not by where it
// sits among the fields. An eight-byte atomic on a misaligned cell is not one.
module FieldAlignment;

import Standard.Threading;

extern "C" int printf(byte* format, ...);

[Align(8)]
struct Cell
{
    public long Value;
}

class Base
{
    public int Pad;
    public Cell First;
}

class Derived : Base
{
    public byte Tag;
    public Cell Second;
}

uint Misalignment(byte* address) => (uint)((nuint)address % 8u);

int Main()
{
    for (int i = 0; i < 3; i++)
    {
        var d = new Derived();
        printf("%u %u\n", Misalignment((byte*)&d.First.Value), Misalignment((byte*)&d.Second.Value));
    }

    var counter = new AtomicLong(40);
    counter.Add(2);
    printf("%lld\n", counter.Read());
    return 0;
}
