// SPDX-License-Identifier: 0BSD
//
// A variable that crosses the C boundary, in both directions.
//
// `extern "C"` already named a function defined elsewhere; this is the same
// thing for storage. It matters because a C library's surface is not only its
// entry points -- `environ`, `optarg`, `stdin` and `timezone` are variables --
// and without this the only way to reach one is a C shim whose whole content
// is a getter, which is exactly the "no bindings, no glue" claim failing.
//
// There is one global on each side of each of these names. Nothing is copied
// and nothing is marshalled: `probe_counter` here and `probe_counter` in
// native.c are one `int` at one address.
module ExternVariables;

import Standard.Console;

// Declared here, defined in native.c.
extern "C" int   probe_counter;
// `long` here is 64 bits and always is, which is C's `long long` rather than
// its `long` -- C's is 32 bits on Windows. Getting that wrong on a *variable*
// is worse than getting it wrong on a function: there is no call to go wrong,
// only a load of the declared width from an address that holds less.
extern "C" long  probe_wide;
extern "C" byte* probe_name;

// Defined here, read by native.c. An exported one may have an initializer,
// because this side owns the storage; an imported one may not (SL0702).
export "C" int sl_depth = 5;
export "C" int sl_flags;

extern "C" void probe_bump();
extern "C" int  probe_read();
extern "C" int  sl_depth_from_c();
extern "C" int  sl_flags_from_c();
extern "C" void set_sl_flags(int value);

int Main() {
    // What C's own initializer left there, read from Stainless.
    Console.WriteLine($"counter {probe_counter}");
    Console.WriteLine($"wide {probe_wide}");
    Console.WriteLine($"name {Text.FromNullTerminated(probe_name)}");

    // Written here, seen there.
    probe_counter = 41;
    Console.WriteLine($"c reads {probe_read()}");

    // Written there, seen here.
    probe_bump();
    Console.WriteLine($"after bump {probe_counter}");

    // Read-modify-write through the global, which is a load and a store to the
    // same address rather than anything special.
    probe_counter = probe_counter + 100;
    Console.WriteLine($"after add {probe_counter} and c agrees {probe_read()}");

    // A wider type, to show the load is the declared width rather than int.
    probe_wide = 8589934592;
    Console.WriteLine($"wide now {probe_wide}");

    // The export direction: storage this program defines under a name C reaches.
    Console.WriteLine($"depth {sl_depth} c reads {sl_depth_from_c()}");
    Console.WriteLine($"flags {sl_flags} c reads {sl_flags_from_c()}");

    sl_depth = 99;
    set_sl_flags(3);
    Console.WriteLine($"depth {sl_depth} c reads {sl_depth_from_c()}");
    Console.WriteLine($"flags {sl_flags} c reads {sl_flags_from_c()}");

    return 0;
}
