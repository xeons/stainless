// SPDX-License-Identifier: 0BSD
//
// Conditional compilation, in the form C# has it. What is printed has to be the
// same on every platform for this to be a test, so most of what is checked is
// that the directives agree with each other rather than what they agree on.
#define EXTRA
#undef EXTRA
#define KEPT

module Conditional;

import Standard.Console;

// A branch that is not taken is never lexed, let alone parsed. This one is
// deliberately not valid Stainless, and proves it.
#if NEVER_DEFINED
    ((( this is not a declaration, and "the string is not closed
#endif

// Exactly one of these is compiled, whichever platform this is.
#if WINDOWS
String Platform() { return "a platform"; }
#elif LINUX
String Platform() { return "a platform"; }
#elif MACOS
String Platform() { return "a platform"; }
#else
String Platform() { return "no platform at all"; }
#endif

// UNIX and WINDOWS are exclusive, and one of them holds.
#if (WINDOWS && !UNIX) || (UNIX && !WINDOWS)
String Exclusive() { return "exclusive"; }
#else
String Exclusive() { return "both or neither"; }
#endif

// STAINLESS is always defined; a name nobody defined is false.
#if STAINLESS && !SOMETHING_NOBODY_DEFINED
String Builtin() { return "builtin"; }
#else
String Builtin() { return "missing"; }
#endif

// #undef takes a symbol away again.
#if EXTRA
String Defines() { return "undef did nothing"; }
#elif KEPT
String Defines() { return "define and undef"; }
#else
String Defines() { return "neither"; }
#endif

// -D reaches the same table as #define; defines.txt passes this one.
#if FASTMATH
String Flag() { return "fastmath"; }
#else
String Flag() { return "plain"; }
#endif

// Nesting, including a group inside a branch that is not taken.
#if KEPT
    #if FASTMATH
String Nested() { return "kept and fast"; }
    #else
String Nested() { return "kept and plain"; }
    #endif
#else
    #if FASTMATH
String Nested() { return "unreachable"; }
    #else
String Nested() { return "unreachable"; }
    #endif
#endif

#region a region is folded by an editor and means nothing here
String Region() { return "region"; }
#endregion

// A directive inside a body chooses statements rather than declarations.
int Width() {
#if X64 || ARM64
    return 64;
#else
    return 32;
#endif
}

int Main() {
    Console.WriteLine(Platform());
    Console.WriteLine(Exclusive());
    Console.WriteLine(Builtin());
    Console.WriteLine(Defines());
    Console.WriteLine(Flag());
    Console.WriteLine(Nested());
    Console.WriteLine(Region());
    Console.WriteLine(Text.FromInteger(Width()));
    return 0;
}
