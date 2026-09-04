// What `offsetof` will not answer.
module ErrLayoutQueries;

public struct Flags {
    public uint A : 3;
    public uint B : 5;
}

public interface IThing { int Go(); }

int Main() {
    // A bit-field has no byte offset of its own — it shares a storage unit with
    // its neighbours, and the number a caller would want is the unit's. C
    // refuses this too.
    nuint a = offsetof(Flags, A);                   // SL0482

    // An interface reference is a pointer to an object; there is no layout here
    // to take an offset into.
    nuint b = offsetof(IThing, Go);                 // SL0480

    // A field that is not there.
    nuint c = offsetof(Flags, Missing);             // SL0481
    return 0;
}
