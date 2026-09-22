// SPDX-License-Identifier: 0BSD
//
// A real in-process COM server, written in Stainless and called from C++.
//
// There is no marshalling layer here and nothing is generated. `IGreeter`
// below is the same vtable the C++ side declares in greeter.h by hand, the
// CLSID is the same sixteen bytes, and the object the host ends up holding is
// an ordinary Stainless object -- header, fields, destructor, ARC -- that
// happens to present a COM vtable.
//
// What makes it a *server* rather than an object you could pass around is the
// two exports at the bottom. `DllGetClassObject` is how COM asks a module
// for a class it has never seen, and answering it is what lets the host say
// "make me one of these" with nothing but a CLSID.
module Greeter;

import Standard.Com;
import Standard.Console;
import Standard.Text;

/// Write a line and make it appear now.
///
/// A shared library has its own stdout buffer, so without the flush every line
/// below would arrive in a lump when the module detaches -- long after the
/// host's output, and saying nothing about the order the two actually ran in.
void WriteLineAndFlush(String line)
{
    Console.WriteLine(line);
    Console.Flush();
}

// ---------------------------------------------------------------- contract

/// What the host calls. Ordinary COM: an HRESULT back, results through
/// pointers, and every slot after IUnknown's three.
[Guid("9d2f5f7a-1c64-4a3b-8f0e-7d5a2c9b4e10")]
public com interface IGreeter
{
    /// Adds to the running total and reports it.
    int Greet(int times, int* total);

    /// The total so far, without changing it.
    int Total(int* total);
}

/// A second interface on the same object, so QueryInterface has something to
/// answer that is not the one the host already holds.
[Guid("b71e0c48-3a95-4f2d-9c11-6e8a0d3f5b27")]
public com interface ICounter
{
    int Reset();
}

// ------------------------------------------------------------------ object

/// The class itself. `[Guid]` here is a **CLSID** rather than an IID: it names
/// the class, which is what a caller holding nothing asks for.
///
/// The constructor takes nothing because activation has nothing to pass
/// (SL0611). Everything else is an ordinary com class.
[Guid("5a1c8e30-2b47-4d16-a9f3-c04e7b81d629")]
public com class Greeter : IGreeter, ICounter
{
    int _total;

    public Greeter()
    {
        _total = 0;
        WriteLineAndFlush("[stainless] Greeter constructed");
    }

    ~Greeter()
    {
        WriteLineAndFlush("[stainless] Greeter destroyed");
    }

    public int Greet(int times, int* total)
    {
        if (total == null)
            return Com.PointerError;

        this._total = this._total + times;
        WriteLineAndFlush("[stainless] Greet(" + Text.FromInteger((long)times) +
            ") -> " + Text.FromInteger((long)this._total));
        *total = this._total;
        return Com.Ok;
    }

    public int Total(int* total)
    {
        if (total == null)
            return Com.PointerError;
        *total = this._total;
        return Com.Ok;
    }

    public int Reset()
    {
        WriteLineAndFlush("[stainless] Reset");
        _total = 0;
        return Com.Ok;
    }
}

// ------------------------------------------------------------------ server

/// The entry point COM asks a module for a class through.
///
/// `Com.GetClassObject` answers from the table the compiler built out of every
/// `com class` carrying a `[Guid]`, so adding a class to this library is
/// declaring one and nothing else. What comes back is an `IClassFactory` the
/// host calls `CreateInstance` on.
export "C" __stdcall int DllGetClassObject(Guid* clsid, Guid* iid, byte** result)
{
    return Com.GetClassObject(clsid, iid, result);
}

/// Whether the host may unload this module: S_OK once no object this module
/// made is still held, and S_FALSE while one is, because unloading then would
/// leave that object's vtable pointing into code that is gone.
export "C" __stdcall int DllCanUnloadNow()
{
    return Com.CanUnloadNow();
}
