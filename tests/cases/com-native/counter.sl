// COM across a real C boundary, in both directions.
//
// The `com` case proves a COM object works inside one Stainless program, which
// it would do whatever convention the compiler picked, as long as it picked the
// same one at both ends. This one proves the convention is C's: the vtables
// below are declared in counter.c the way any COM header declares one, and on
// x86 that means `__stdcall` -- the callee removes the arguments, so a caller
// that disagreed would unbalance the stack and the program would not survive
// the second call.
//
// Both directions, because they fail differently. Stainless handing C an object
// exercises the adjustor thunks and the runtime's IUnknown; C handing Stainless
// one exercises the call sites the compiler emits.
module ComNative;

import Standard.Console;
import Standard.Text;
import Standard.Com;

[Guid("58ba1f7c-2e04-4a16-9c8d-31e07f6ab254")]
public com interface ICounter
{
    int Add(int by);
    int Value { get; }
}

/// Implemented here, called from C.
public com class Counter : ICounter
{
    int _total;

    public Counter() => _total = 0;

    public int Add(int by)
    {
        _total = _total + by;
        return _total;
    }
    public int Value => _total;

    ~Counter() { Console.WriteLine("counter destroyed"); }
}

// C's half. `count_through` is handed a borrowed ICounter and calls it; the
// other two hand back an ICounter that C implements, already AddRef'd.
extern "C" int count_through(byte* it);
extern "C" byte* native_counter();
extern "C" int native_live();

void Say(String label, int value)
{
    Console.WriteLine(label + " " + Text.FromInteger((long)value));
}

public void Main()
{
    // --- C calling a Stainless com class -------------------------------
    {
        Counter counter = new Counter();
        ICounter it = counter;

        Say("c saw          ", count_through((byte*)it));
        Say("after c        ", it.Value);
        Console.WriteLine("dropping:");
    }
    Console.WriteLine("dropped");

    // --- Stainless calling a C com class -------------------------------
    //
    // native_counter returns an owned reference, which is what a COM factory
    // does; ARC releases it at the end of the block, and native_live then says
    // C saw the release.
    {
        ICounter native = (ICounter)native_counter();
        Say("native add 7   ", native.Add(7));
        Say("native add 2   ", native.Add(2));
        Say("native value   ", native.Value);
        Console.WriteLine("releasing:");
    }
    Say("native live    ", native_live());

    Console.WriteLine("end of Main");
}
