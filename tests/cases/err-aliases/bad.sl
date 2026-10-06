// What an alias and an opaque type refuse.
module Bad;

import Platform;

// A ring of aliases names no type. Nothing below uses these, which is the point:
// an alias resolved only where it is named would let a ring through in silence.
using Ring = Loop;                              // SLC0059
using Loop = Ring;
using Me = Me;                                  // SLC0059

// Only a struct may be written with no body. A class is reached through a
// pointer this compiler has to lay out; a union and a variant are nothing but
// their contents.
public class Nope;                              // SLI0022
public union Never;                             // SLI0022 (and SLI0009, which is also true)
public struct Generic<T>;                       // SLI0022
public struct Implements__ : IThing;            // SLC0013: nothing to answer Go

public interface IThing { int Go(); }

// An incomplete type has no size, so there is no value of one to have. Each of
// these is the same mistake in a different place, and each is caught at the one
// door every written type comes through.
public struct Holder
{
    public HWND__ Inline;                       // SLI0023
}

nuint Sizes() => sizeof(HWND__); // SLI0023
nuint Aligns() => alignof(HWND__); // SLI0023
HWND__ Give() => null; // SLI0023
void Take(HWND__ window) { }                    // SLI0023
void ByRef(ref HWND__ window) { }               // SLI0023

// An alias belongs to a module, which is what this language has instead of a
// namespace.
public struct Outer
{
    using Inner = int;                          // SLC0060
    public int X;
}

int Main()
{
    // The mix-up the opaque types exist to catch: both are pointers, and they
    // are not the same pointer.
    HDC device = null;
    int wide = Width(device);                   // SLT0015

    HWND__[] many = new HWND__[2];              // SLI0023
    return wide;
}
