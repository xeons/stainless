// SPDX-License-Identifier: 0BSD
//
// The tour's second module, which exists so that the first one has something
// to import (§1.4). Everything here is about a *name* rather than about code:
// aliases, handles that are told apart, and the two declarations that describe
// something living outside the program.
//
// A module is reached by the last segment of its name, so this is `Platform.`
// at a use site even though it is declared as `Tour.Platform`.
module Tour.Platform;

// --------------------------------------------------------------- §2.2.1

// C's incomplete type: declared here, laid out nowhere, and never completed.
// The only thing that can be done with one is point at it -- which is the whole
// of what a handle is.
public struct Handle__;
public struct Cursor__;

// --------------------------------------------------------------- §1.5

/// A strong-ish alias: two pointers to two undeclared types are two types, so
/// a `Cursor` cannot be passed where a `Slot` belongs.
public using Slot   = Handle__*;
public using Cursor = Cursor__*;

/// A weak alias over a primitive. It converts nothing and costs nothing; what
/// it buys is a signature that says what the number is for.
public using Code = int;

/// An alias may name another alias.
public using Status = Code;

/// And a compound type, which is where the reading is worst without one.
public using Adjust = Transform;

public delegate int Transform(int value);

public const Status Fine   = 0;
public const Status Broken = -1;

// --------------------------------------------------------------- §10

/// Which platform this was built for, decided at compile time. `WINDOWS`,
/// `UNIX`, `LINUX`, `MACOS` and `STAINLESS` are defined by the compiler; `-D`
/// adds more.
public String Family() {
#if WINDOWS
    return "windows";
#elif LINUX
    return "linux";
#elif MACOS
    return "macos";
#else
    return "somewhere else";
#endif
}

/// A symbol the tour never defines, so the `#else` is what survives. Nothing
/// in the discarded branch is lexed, let alone bound.
public String Mood() {
#if TOUR_IS_GRUMPY
    this line is not even tokenized
#else
    return "cheerful";
#endif
}

// --------------------------------------------------------------- §8

// C, declared. `...` is a variadic and only an `extern` may have one.
public extern "C" int printf(byte* format, ...);
public extern "C" nuint strlen(byte* text);

// The tour's own C file, which is compiled alongside it and calls back into
// Stainless through a delegate.
public extern "C" int c_apply_twice(Adjust f, int value);
public extern "C" int c_sum_pair(PlainPair pair);

/// A struct of plain data, which is the only kind that may cross `extern "C"`:
/// C would copy the bytes and leave a reference count behind.
public struct PlainPair {
    public int A;
    public int B;
}

// --------------------------------------------------------------- §8.1

// C++, reached by mangling the signature the way the target's own compiler
// does -- Itanium on Linux, MSVC's scheme on Windows. No `extern "C"` on
// either side, and no shim in between.
public extern "C++" double tour::area(double width, double height);
public extern "C++" int cpp_round_trip(int n);

/// The other direction: this is emitted under the C++ name `tour::Doubled`,
/// and native.cpp calls it as one.
public export "C++" int tour::Doubled(int n) { return n * 2; }

// --------------------------------------------------------------- §8.6

// A file names the library it needs, rather than every program that compiles
// it repeating the name on the command line. MSVC's spelling, and the only
// pragma Stainless has.
#if WINDOWS
#pragma comment(lib, "kernel32")
#else
#pragma comment(lib, "m")
#endif

// --------------------------------------------------------------- §8, back out

/// `export "C"` is the other direction: this one is in the binary's export
/// table under exactly this name, and the C file calls it.
public export "C" int tour_triple(int value) { return value * 3; }

/// Handles are made from integers here, there being no real window to ask for.
/// What matters is that the two stay apart on the way through.
public Slot   SlotAt(nuint n)   { return (Slot)n; }
public Cursor CursorAt(nuint n) { return (Cursor)n; }

public nuint NumberOf(Slot slot) { return (nuint)slot; }

public Status Check(Slot slot, Cursor cursor) {
    if (slot == null)   { return Broken; }
    if (cursor == null) { return Broken; }
    return Fine;
}
