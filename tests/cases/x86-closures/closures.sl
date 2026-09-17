// A closure on a target where a pointer is four bytes.
//
// A closure is two words, a function and a receiver, and the emitter has
// always written it as `{ ptr, ptr }`. The binder wrote its layout out by hand
// as sixteen bytes with the receiver at eight, so on x86 `sizeof` said sixteen
// of an eight-byte struct and every field after a closure was placed eight
// bytes past where the emitted struct had it.
module X86Closures;

import Standard.Console;

public closure int Op(int x);

class Scale
{
    private int _by;

    public Scale(int by)
    {
        _by = by;
    }

    public int Apply(int x) => x * _by;
}

struct Holder
{
    public Op F;
    public int After;
}

struct Pair
{
    public byte Tag;
    public Op First;
    public Op Second;
    public int Last;
}

int Main()
{
    Console.WriteLine($"closure   {sizeof(Op)}");
    Console.WriteLine($"after     {offsetof(Holder, After)}");
    Console.WriteLine($"holder    {sizeof(Holder)}");
    Console.WriteLine($"second    {offsetof(Pair, Second)}");
    Console.WriteLine($"last      {offsetof(Pair, Last)}");
    Console.WriteLine($"pair      {sizeof(Pair)}");

    // Written and read back through the fields, so that a binder and an
    // emitter disagreeing about where `After` is shows up as a wrong value
    // and not only as a wrong number from `offsetof`.
    var scale = new Scale(3);
    Holder holder;
    holder.F = scale.Apply;
    holder.After = 41;
    Console.WriteLine($"call      {holder.F(5)} {holder.After}");

    Pair pair;
    pair.Tag = 7u;
    pair.First = new Scale(2).Apply;
    pair.Second = new Scale(10).Apply;
    pair.Last = 99;
    Console.WriteLine($"pair      {pair.First(4)} {pair.Second(4)} {pair.Last} {pair.Tag}");
    return 0;
}
