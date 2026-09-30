// SPDX-License-Identifier: 0BSD
//
// A generic instantiated in a signature is laid out once its layout can be
// trusted, which is after [Packed] and [Align] have been read -- including
// onto the instantiation itself, from its template.
module PackedInstantiations;

import Standard.Console;

[Packed]
public struct Squeezed
{
    public byte Flag;
    public long Value;
}

[Align(16)]
public struct Wide
{
    public int Value;
}

public struct Box<T>
{
    public T Held;
}

[Packed]
public struct PackedBox<T>
{
    public byte Flag;
    public T Held;
}

// Named in fields, so each instantiation is made while members are declared.
public struct Holder
{
    public Box<Squeezed> Squeezed;
    public Box<Wide> Wide;
    public PackedBox<long> Packed;
}

void Show(String name, nuint size) => Console.WriteLine(name + " " + Text.FromInteger((long)size));

int Main()
{
    Show("Squeezed", sizeof(Squeezed));
    Show("Box<Squeezed>", sizeof(Box<Squeezed>));
    Show("Wide", sizeof(Wide));
    Show("Box<Wide>", sizeof(Box<Wide>));
    Show("PackedBox<long>", sizeof(PackedBox<long>));
    Show("Holder", sizeof(Holder));
    return 0;
}
