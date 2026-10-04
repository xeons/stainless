// ndouble is C's long double on every target: x87's 80 bits on x86 System V,
// IEEE quad on ARM64 Linux, and a double on Windows and Apple silicon. Every
// check is against what clang makes of long double here, so the case says the
// same thing on each target while the bits underneath differ.
module NDouble;

import Standard.Console;

public struct Tagged
{
    public int Tag;
    public ndouble Value;
}

extern "C"
{
    nuint ld_size();
    nuint ld_align();
    nuint tagged_size();
    nuint tagged_value_at();
    ndouble ld_scale(ndouble x, int by);
    ndouble ld_third();
    ndouble tagged_sum(Tagged tagged);
    Tagged tagged_make(int tag);
}

int Main()
{
    // Layout, against C's.
    Console.WriteLine($"size and alignment agree: {sizeof(ndouble) == ld_size() && alignof(ndouble) == ld_align()}");
    Console.WriteLine($"struct agrees: {sizeof(Tagged) == tagged_size() && offsetof(Tagged, Value) == tagged_value_at()}");

    // Across the C boundary both ways, as a value and inside a struct.
    ndouble half = 0.5;
    Console.WriteLine($"scaled {ld_scale(half, 6)}");
    Tagged made = tagged_make(5);
    Console.WriteLine($"made {made.Tag} {made.Value}, summed {tagged_sum(made)}");

    // C's third is the same number this target's arithmetic makes.
    ndouble third = (ndouble)1 / 3;
    Console.WriteLine($"third agrees: {third == ld_third()}");

    // float and double widen to it; it narrows only by a cast.
    float single = 1.25f;
    double wide = 2.5;
    ndouble total = single + wide;
    double back = (double)total;
    Console.WriteLine($"total {total}, back {back}, compared {total > wide}");

    // Integers both ways, and a constant that is exact in every width.
    ndouble big = 1 << 20;
    long whole = (long)(big * 3);
    Console.WriteLine($"integers {whole}, constant {(ndouble)0.125 * 8}");
    return 0;
}
