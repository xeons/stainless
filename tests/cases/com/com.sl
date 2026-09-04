// COM as a calling convention: `com interface` and `com class`.
//
// A COM interface reference points at a vtable pointer, and the first three
// slots of that vtable are always QueryInterface, AddRef and Release. Nothing
// in that needs an operating system, which is why this case is not marked
// windows-only: what is Windows about COM is activation, and none of that
// appears here.
//
// The two things worth checking are the two the compiler does that C would
// not. ARC drives AddRef and Release, so a COM reference cannot be leaked or
// over-released by forgetting; and `is` and a cast are QueryInterface, so
// asking what an object is goes to the object.
module Com;

import Standard.Console;
import Standard.Text;
import Standard.Com;

// --------------------------------------------------------------- interfaces

/// A root com interface. It extends IUnknown whether or not that is written,
/// because every COM vtable begins with those three slots -- so Greet is slot
/// 3, not slot 0.
[Guid("6a8f2c14-9b3e-4d55-8f21-7c0e5a913d42")]
public com interface IGreeter {
    int Greet(int times);
}

/// A derived one. Its table is IGreeter's with Shout appended, which is what
/// makes an ILoudGreeter reference usable as an IGreeter with no conversion.
[Guid("2d4b7e91-05a6-4c38-b7de-1f83c6209ab5")]
public com interface ILoudGreeter : IGreeter {
    int Shout();
}

/// Nothing here implements this, so it is what a failed QueryInterface looks
/// like.
[Guid("ff10c3d7-6428-49ba-9e05-b3172d8e4c60")]
public com interface IAbsent {
    int Nothing();
}

// ------------------------------------------------------------------ a class

/// An ordinary Stainless object -- header, fields, a destructor -- that also
/// presents COM vtables. The tear-offs sit after the fields, one per interface,
/// each holding a vtable pointer and its own distance back to the object.
public com class Greeter : ILoudGreeter {
    int count;

    public Greeter() { count = 0; }

    public int Greet(int times) {
        count = count + times;
        return count;
    }

    public int Shout() { return count; }

    ~Greeter() { Console.WriteLine("greeter destroyed"); }
}

/// A second class behind the same interface, so QueryInterface has something
/// to say no to.
public com class Quiet : IGreeter {
    public int Greet(int times) { return times; }
}

// ------------------------------------------------------------------ helpers

void Say(String label, int value) {
    Console.WriteLine(label + " " + Text.FromInteger((long)value));
}

/// Returns a COM reference to an object nothing else holds.
///
/// The local dies at the end of this function. If ARC were not calling AddRef
/// through the vtable, so would the object, and the caller would read freed
/// memory.
IGreeter Make() {
    var greeter = new Greeter();
    return greeter;
}

/// Takes the base interface and asks the object whether it is really the
/// derived one. The compiler cannot answer this: the object does.
void Describe(IGreeter greeter) {
    Console.WriteLine("  is ILoudGreeter " + Text.FromBool(greeter is ILoudGreeter));
    Console.WriteLine("  is IAbsent      " + Text.FromBool(greeter is IAbsent));

    if (greeter is ILoudGreeter) {
        ILoudGreeter loud = (ILoudGreeter)greeter;
        Say("  shout          ", loud.Shout());
    }
}

public void Main() {
    // --- dispatch -----------------------------------------------------
    //
    // Two loads: the reference points at the vtable pointer, so there is no
    // object header to go through first.
    var greeter = new Greeter();
    ILoudGreeter loud = greeter;

    Say("greet 3 ->", loud.Greet(3));
    Say("shout   ->", loud.Shout());

    // Free: a COM vtable begins with its base's slots, so the same pointer
    // already answers IGreeter's calls.
    IGreeter plain = loud;
    Say("greet 2 ->", plain.Greet(2));

    // --- QueryInterface ------------------------------------------------
    Console.WriteLine("Greeter:");
    Describe(plain);

    Console.WriteLine("Quiet:");
    Describe(new Quiet());

    // --- lifetime ------------------------------------------------------
    //
    // The object made inside Make outlives the local that made it, and dies
    // when the last COM reference to it does.
    Console.WriteLine("made:");
    {
        IGreeter kept = Make();
        Say("  greet 5 ->", kept.Greet(5));

        {
            IGreeter second = kept;
            Say("  greet 1 ->", second.Greet(1));
        }

        Say("  still alive ->", kept.Greet(0));
        Console.WriteLine("  dropping:");
    }
    Console.WriteLine("  dropped");

    // --- iidof ---------------------------------------------------------
    //
    // The address of the constant the [Guid] folded to, so the same interface
    // twice is the same pointer and neither costs an instruction.
    Guid* first = iidof(IGreeter);
    Guid* again = iidof(IGreeter);
    Console.WriteLine("iidof is stable: " + Text.FromBool(first == again));
    Console.WriteLine("iidof data1: " + Text.FromInteger((long)first->Data1));

    Console.WriteLine("end of Main");
}
