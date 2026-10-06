// What an inline array may not be.
module ErrFixedArrays;

int Size() => 4;

// The length is part of the type, so it has to be known now.
public struct NotConstant { public int[Size()] Values; }        // SLT0050

// An array of nothing is nothing.
public struct Empty { public int[0] Values; }                   // SLT0051

// There is no array of 'void', for the same reason there is no array of it.
public struct OfVoid { public void[4] Values; }                 // SLT0024

// A value has to stay addressable. This is far past any real struct, and
// exists so a typo is a diagnostic rather than a nonsensical size.
public struct Vast { public int[1073741824] Values; }           // SLT0052

// A counted reference would have to be retained element by element on every
// copy of whatever holds the array. `T[]` is the one counted object instead.
public struct Counted { public String[4] Names; }               // SLO0020

// C decays an array parameter to a pointer; copying every element here would
// be neither that nor cheap.
void ByValue(int[4] values) { }                                 // SLT0054

int Main()
{
    int[4] a;

    // The length is in the type, so this is answered now rather than at run
    // time -- which is strictly better than what `T[]` can do.
    a[9] = 1;                                                   // SLT0053

    // An inline array has a length and nothing else.
    nuint n = a.Capacity;                                       // SLN0013
    return 0;
}
