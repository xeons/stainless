// SPDX-License-Identifier: 0BSD
module Bad;

// A slot is laid out as its element or as an optional of it, depending on
// whether the element has a zero value -- which is not a promise C can hold
// Stainless to, so a slot does not cross, bare or inside a struct.
struct Pair { public int Count; public Slot<int> Held; }

extern "C" void consume(Slot<int> held);

export "C" Pair produce()
{
    Pair made;
    made.Count = 0;
    return made;
}

int Main() => 0;
