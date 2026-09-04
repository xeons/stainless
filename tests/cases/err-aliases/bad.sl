// What an alias and an opaque type refuse.
module Bad;

import Platform;

// A ring of aliases names no type. Nothing below uses these, which is the point:
// an alias resolved only where it is named would let a ring through in silence.
using Ring = Loop;                              // SL0522
using Loop = Ring;
using Me = Me;                                  // SL0522

// Only a struct may be written with no body. A class is reached through a
// pointer this compiler has to lay out; a union and a variant are nothing but
// their contents.
public class Nope;                              // SL0523
public union Never;                             // SL0523 (and SL0467, which is also true)
public struct Generic<T>;                       // SL0523
public struct Implements__ : IThing;            // SL0302, which says it all

public interface IThing { int Go(); }

// An incomplete type has no size, so there is no value of one to have. Each of
// these is the same mistake in a different place, and each is caught at the one
// door every written type comes through.
public struct Holder {
    public HWND__ Inline;                       // SL0524
}

nuint Sizes() { return sizeof(HWND__); }        // SL0524
nuint Aligns() { return alignof(HWND__); }      // SL0524
HWND__ Give() { return null; }                  // SL0524
void Take(HWND__ window) { }                    // SL0524
void ByRef(ref HWND__ window) { }               // SL0524

// An alias belongs to a module, which is what this language has instead of a
// namespace.
public struct Outer {
    using Inner = int;                          // SL0525
    public int X;
}

int Main() {
    // The mix-up the opaque types exist to catch: both are pointers, and they
    // are not the same pointer.
    HDC device = null;
    int wide = Width(device);                   // SL0262

    HWND__[] many = new HWND__[2];              // SL0524
    return wide;
}
