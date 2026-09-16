// A calling convention on a delegate, and a pointer cast to one.
//
// Together these are what dynamic loading needs: a symbol looked up by name
// arrives as a `void*`, and the only useful thing to do with one is call it.
// `Standard.Drawing` resolves every GDI+ and libgd entry point this way.
module Registry;

import Standard.Console;

/// The convention goes where `extern "C" __stdcall` already puts it: in front
/// of the return type. It means nothing on x64 and everything on x86, where the
/// callee removes the arguments.
public delegate __stdcall int ScaledSum(int a, int b, int c, int d);
public delegate __stdcall int Difference(int a, int b);

/// And one without, to prove the two are not emitted the same way.
public delegate int PlainProduct(int a, int b);

extern "C"
{
    void* lookup(byte* name);
}

int Main()
{
    // Exactly the shape GetProcAddress and dlsym answer with.
    void* first = lookup("scaled_sum".ToPointer());
    void* second = lookup("difference".ToPointer());
    void* third = lookup("plain_product".ToPointer());
    void* missing = lookup("nothing_here".ToPointer());

    Console.WriteLine($"found three: {first != null && second != null && third != null}");
    Console.WriteLine($"and not a fourth: {missing == null}");

    // The cast is the second half of this case: a pointer converts to a
    // delegate explicitly, and only explicitly.
    var sum = (ScaledSum)first;
    var difference = (Difference)second;
    var product = (PlainProduct)third;

    Console.WriteLine($"stdcall, four arguments: {sum(1, 2, 3, 4)}");
    Console.WriteLine($"stdcall, two arguments:  {difference(10, 4)}");
    Console.WriteLine($"cdecl, two arguments:    {product(6, 7)}");

    // Called twice more, because a convention mismatch usually survives one
    // call and takes the stack with it on the next.
    Console.WriteLine($"and again:               {sum(5, 5, 5, 5)}");
    Console.WriteLine($"and again:               {difference(3, 8)}");

    // Back to a pointer, which is the other direction of the same cast, and
    // what a program storing a resolved symbol in a table would do.
    void* returned = (void*)sum;
    Console.WriteLine($"and back to a pointer:   {returned == first}");

    return 0;
}
