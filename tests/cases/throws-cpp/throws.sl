// SPDX-License-Identifier: 0BSD
//
// `[Throws]` on a C function that C++ implements: a C++ exception it throws
// comes back as a value of kind `Cpp`, and one that throws nothing answers
// what it produced.
module CppThrows;

import Standard.Console;
import Standard.Text;

/// Throws a std::runtime_error for an odd number.
[Throws]
extern "C" Result<int, ForeignException> SLCppHalve(int number);

/// Throws an int for a negative number.
[Throws]
extern "C" ForeignException? SLCppCheck(int number);

String Describe(ForeignException thrown) =>
    thrown.Kind == ForeignExceptionKind.Cpp ? "a C++ exception" : "something else";

int Main()
{
    var half = SLCppHalve(8);
    Console.WriteLine("halve 8: " + (half.Ok ? FromInteger(half.Value) : Describe(half.Error)));
    half = SLCppHalve(7);
    Console.WriteLine("halve 7: " + (half.Ok ? FromInteger(half.Value) : Describe(half.Error)));

    var checked = SLCppCheck(1);
    Console.WriteLine("check 1: " + (checked == null ? "fine" : Describe((ForeignException)checked)));
    checked = SLCppCheck(-1);
    Console.WriteLine("check -1: " + (checked == null ? "fine" : Describe((ForeignException)checked)));
    return 0;
}
