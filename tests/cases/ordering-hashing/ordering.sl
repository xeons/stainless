// SPDX-License-Identifier: 0BSD
//
// `CompareTo` and `HashCode` on the types that cannot implement an interface.
//
// A primitive is not a class, so `int` cannot be declared to implement
// `IComparable<int>`; the binder recognises the two names and lowers each to a
// function in `Standard`, written in Stainless. What is pinned here is the
// handful of answers those have to get right and which an ordinary `Sort` of
// ordinary values would never ask for: where NaN sorts, that a `ulong` past
// 2^63 is large rather than negative, and that values which compare equal hash
// equal.
module OrderingHashing;

import Standard.Console;
import Standard.Text;

/// -1, 0 or 1 as text, so a comparison's sign is what is compared and not
/// whatever magnitude a byte-wise answer happened to have.
String Sign(int comparison)
{
    if (comparison < 0)
        return "-1";
    if (comparison > 0)
        return "1";
    return "0";
}

void Say(String what, String value)
{
    Console.WriteLine(what + " " + value);
}

int Main()
{
    // ------------------------------------------------------------- integers

    Say("long/ordered", Sign((-5L).CompareTo(3L)));
    Say("long/equal", Sign(7L.CompareTo(7L)));
    Say("long/extremes", Sign(9223372036854775807L.CompareTo(-9223372036854775808L)));

    // Past 2^63. Read as a signed number this is negative, and the whole
    // reason the unsigned comparison is a function of its own.
    ulong big = 18446744073709551615u;
    Say("ulong/large", Sign(big.CompareTo(1u)));
    Say("ulong/equal", Sign(big.CompareTo(big)));

    // -------------------------------------------------------------- doubles

    double zero = 0.0;
    double negativeZero = -1.0 * 0.0;
    double nan = zero / zero;
    double otherNan = (1.0 / zero) - (1.0 / zero);
    double infinity = 1.0 / zero;

    Say("double/ordered", Sign((-1.5).CompareTo(2.5)));

    // A sort needs a total order or it does not terminate, so NaN is below
    // every number and equal to itself.
    Say("double/nan-below", Sign(nan.CompareTo(-infinity)));
    Say("double/nan-equals-nan", Sign(nan.CompareTo(otherNan)));
    Say("double/infinity-above", Sign(infinity.CompareTo(1e308)));

    // The two values that would break "equal compares, equal hashes".
    Say("double/zeroes-compare", Sign(zero.CompareTo(negativeZero)));
    Say("double/zeroes-hash", zero.HashCode() == negativeZero.HashCode() ? "same" : "differ");
    Say("double/nans-hash", nan.HashCode() == otherNan.HashCode() ? "same" : "differ");

    // ----------------------------------------------------------------- text

    Say("text/ordered", Sign("apple".CompareTo("banana")));

    // Two objects with the same bytes, and then one object twice: a literal is
    // interned, so the second of these is the identity test and the first is
    // not.
    Say("text/equal", Sign(("app" + "le").CompareTo("apple")));
    Say("text/identity", Sign("apple".CompareTo("apple")));

    // A prefix is shorter and therefore first, which the shared bytes cannot
    // decide on their own.
    Say("text/prefix", Sign("hell".CompareTo("hello")));
    Say("text/empty", Sign("".CompareTo("a")));

    // Ordinal, by byte: upper case is below lower case, and beyond ASCII the
    // order is the code points' own because UTF-8 preserves it.
    Say("text/case", Sign("Z".CompareTo("a")));
    Say("text/beyond-ascii", Sign("é".CompareTo("世")));

    Say("text/equal-hash", "apple".HashCode() == ("app" + "le").HashCode() ? "same" : "differ");
    Say("text/unequal-hash", "apple".HashCode() == "banana".HashCode() ? "same" : "differ");

    // ---------------------------------------------------------------- enums

    Say("enum/ordered", Sign(Weekday.Monday.CompareTo(Weekday.Friday)));
    Say("enum/equal", Sign(Weekday.Friday.CompareTo(Weekday.Friday)));

    return 0;
}

enum Weekday
{
    Monday,
    Friday,
}
