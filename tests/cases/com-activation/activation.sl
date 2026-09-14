// SPDX-License-Identifier: 0BSD
//
// Activation: being asked for a class by CLSID rather than handed an object.
//
// The `com` and `com-native` cases prove a com class works and that its
// convention is C's. This one proves the piece those two leave out -- that
// something holding nothing but sixteen bytes can ask this program for an
// object and get one, which is what `DllGetClassObject` is for and what makes
// a Stainless library usable as a real COM server.
//
// It runs in one binary rather than across a DLL boundary, because that is
// what the harness builds. Everything under test is the same either way: the
// factory table the compiler emits, the IClassFactory the runtime wraps it in,
// and the constructor and destructor running at the right moments. What a real
// DLL adds is LoadLibrary, and samples/com is where that is shown.
module Activation;

import Standard.Com;
import Standard.Console;
import Standard.Text;

[Guid("9d2f5f7a-1c64-4a3b-8f0e-7d5a2c9b4e10")]
public com interface IGreeter {
    int Greet(int times, int* total);
    int Total(int* total);
}

/// A second interface, so QueryInterface has something to answer that is not
/// the one the caller already holds.
[Guid("b71e0c48-3a95-4f2d-9c11-6e8a0d3f5b27")]
public com interface ICounter {
    int Reset();
}

/// `[Guid]` on a com class is a CLSID: it names the class, so a caller with no
/// object can ask for one.
[Guid("5a1c8e30-2b47-4d16-a9f3-c04e7b81d629")]
public com class Greeter : IGreeter, ICounter {
    int total;

    public Greeter() {
        total = 0;
        Console.WriteLine("constructed");
    }

    ~Greeter() { Console.WriteLine("destroyed"); }

    public int Greet(int times, int* total) {
        if (total == null) { return Com.PointerError; }
        this.total = this.total + times;
        *total = this.total;
        return Com.Ok;
    }

    public int Total(int* total) {
        if (total == null) { return Com.PointerError; }
        *total = this.total;
        return Com.Ok;
    }

    public int Reset() { total = 0; return Com.Ok; }
}

/// A com class with no CLSID stays unreachable by one, which is the other half
/// of the rule: it can be handed out, never asked for.
public com class Quiet : ICounter {
    public int Reset() { return Com.Ok; }
}

// The COM server entry point, exported exactly as a DLL would export it. Here
// the C++ half calls it directly, which is what LoadLibrary would have found.
export "C" int DllGetClassObject(Guid* clsid, Guid* iid, byte** result) {
    return Com.GetClassObject(clsid, iid, result);
}

export "C" int DllCanUnloadNow() { return Com.CanUnloadNow(); }

/// The C++ half, which does the asking.
extern "C++" int DriveActivation();

public void Main() {
    Console.WriteLine("can unload: " + Text.FromInteger((long)DllCanUnloadNow()));

    int failures = DriveActivation();
    Console.WriteLine("failures: " + Text.FromInteger((long)failures));
}
