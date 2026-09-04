// What an inline array may not be.
module ErrFixedArrays;

int Size() { return 4; }

// The length is part of the type, so it has to be known now.
public struct NotConstant { public int[Size()] Values; }        // SL0487

// An array of nothing is nothing.
public struct Empty { public int[0] Values; }                   // SL0488

// There is no array of 'void', for the same reason there is no array of it.
public struct OfVoid { public void[4] Values; }                 // SL0485

// A value has to stay addressable. This is far past any real struct, and
// exists so a typo is a diagnostic rather than a nonsensical size.
public struct Vast { public int[1073741824] Values; }           // SL0489

// A counted reference would have to be retained element by element on every
// copy of whatever holds the array. `T[]` is the one counted object instead.
public struct Counted { public String[4] Names; }               // SL0486

// C decays an array parameter to a pointer; copying every element here would
// be neither that nor cheap.
void ByValue(int[4] values) { }                                 // SL0491

int Main() {
    int[4] a;

    // The length is in the type, so this is answered now rather than at run
    // time -- which is strictly better than what `T[]` can do.
    a[9] = 1;                                                   // SL0490

    // An inline array has a length and nothing else.
    nuint n = a.Capacity;                                       // SL0313
    return 0;
}
