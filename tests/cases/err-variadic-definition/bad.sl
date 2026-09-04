// A '...' on anything this program defines rather than merely calls.
//
// Calling a C variadic is fine and unaffected -- printf is bound with one three
// lines below. Being one is not: nothing in the language can read the extra
// arguments, so the definition would ignore them while the header written for
// it promised the variadic convention.
module ErrVariadicDefinition;

extern "C" int printf(byte* format, ...);           // fine: called, not defined

// The header would say `int32_t log_line(uint8_t*, ...)` and the definition
// would take one argument.
export "C" int log_line(byte* format, ...) {        // SL0493
    return printf(format);
}

// An ordinary Stainless function has the same hole, and no header to blame.
int Sum(int first, ...) {                           // SL0493
    return first;
}

public class Bag {
    public int Count;

    // A constructor's list threw its '...' away without even a name to report
    // it against, which was the same silence in a smaller place.
    Bag(int count, ...) {                           // SL0493
        Count = count;
    }
}

int Main() {
    var bag = new Bag(1);
    return bag.Count - 1;
}
