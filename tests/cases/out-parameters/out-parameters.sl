// SPDX-License-Identifier: 0BSD
//
// `out` parameters, and the variable a call may declare for one.
//
// At the ABI it is the same pointer `ref` is. What separates them is who has
// to have filled it in: `ref` is a variable the caller already gave a value,
// `out` is one the callee promises to give a value to. That promise is the
// only definite-assignment analysis in the language (SL0600), and it is here
// because this is the one place it is load-bearing -- the caller's variable
// may never have held anything.
//
// The caller's storage is also cleared before the call, so a hole in that
// analysis produces a zero rather than whatever the stack held.
//
// `out` is a **contextual keyword**, and the standard library is what decided
// that: `Convert.sl` and `Encoding.sl` both have a local called `out`.
module OutParameters;

import Standard.Console;
import Standard.Convert;

/// The shape `out` exists for: an answer and whether there was one.
bool TryHalve(int n, out int half) {
    if (n % 2 != 0) { half = 0; return false; }
    half = n / 2;
    return true;
}

/// Two of them, one a counted reference, so ARC has to be right about a
/// variable that was declared by a call.
void Split(String text, out String head, out String tail) {
    head = text.Substring(0u, 1u);
    tail = text.Substring(1u, text.ByteLength() - 1u);
}

/// A parameter handed straight on as somebody else's `out` counts as written:
/// the callee is held to the same promise.
bool Forward(int n, out int half) { return TryHalve(n, out half); }

/// `out` next to the other two modes, to show they travel the same way.
void Compare(in int left, ref int right, out int larger) {
    larger = left > right ? left : right;
    right = left;
}

class Registry {
    String[] names;
    int used;

    public Registry() { names = new String[4]; used = 0; }

    public void Add(String name) { names[used] = name; used++; }

    public bool TryFind(String name, out int at) {
        for (int i = 0; i < used; i++) {
            if (names[i] == name) { at = i; return true; }
        }
        at = -1;
        return false;
    }
}

public int Main() {
    // Declared at the call, type inferred from the parameter.
    if (TryHalve(10, out var five)) { Console.WriteLine($"half     {five}"); }

    // Declared at the call, spelled out.
    if (!TryHalve(7, out int none)) { Console.WriteLine($"odd      {none}"); }

    // A variable that already exists, which `out` overwrites.
    int already = 99;
    TryHalve(8, out already);
    Console.WriteLine($"existing {already}");

    // Counted references, declared by the call.
    Split("hello", out var head, out var tail);
    Console.WriteLine($"split    {head} + {tail}");

    // Passed straight on.
    Forward(12, out var six);
    Console.WriteLine($"forward  {six}");

    // Beside `in` and `ref`.
    int right = 3;
    Compare(10, ref right, out var larger);
    Console.WriteLine($"compare  {larger} and right is now {right}");

    // A method, and the loop that fills nothing.
    var registry = new Registry();
    registry.Add("alpha");
    registry.Add("beta");

    if (registry.TryFind("beta", out var at)) { Console.WriteLine($"found    beta at {at}"); }
    if (!registry.TryFind("gamma", out var missing)) { Console.WriteLine($"missing  {missing}"); }

    // The standard library's own shape, for comparison: a Result carries the
    // value and the failure together, and needs no second variable.
    var parsed = ToLong("41");
    if (parsed.Ok) { Console.WriteLine($"result   {parsed.Value}"); }
    return 0;
}
