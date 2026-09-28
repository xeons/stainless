// `Notify?`: a closure that may hold nothing.
//
// A closure is two words, and its null is a null function word. The nullable
// form is the same two words, compared with null as both, narrowed by a check
// the way `C?` is, and never called until one says there is a function.
module NullableClosures;

import Standard.Console;

public closure void Notify(int value);
public closure String Describe(int value);

public class Counter
{
    public int Total;
    public void Add(int value) => Total += value;
}

public class Source
{
    private Notify? _onChange;

    public void Listen(Notify handler) => _onChange = handler;
    public void Forget() => _onChange = null;
    public bool IsHeard => _onChange != null;

    public void Change(int value)
    {
        if (_onChange is { } handler)
            handler(value);
    }
}

String Show(int value) => $"<{value}>";

String Apply(Describe? describe, int value)
{
    if (describe == null)
        return "none";
    return describe(value);
}

int Main()
{
    var counter = new Counter();
    var source = new Source();

    source.Change(1);
    Console.WriteLine($"{source.IsHeard}");

    source.Listen(counter.Add);
    source.Change(5);
    source.Change(7);
    Console.WriteLine($"{source.IsHeard} {counter.Total}");

    source.Forget();
    source.Change(100);
    Console.WriteLine($"{source.IsHeard} {counter.Total}");

    Notify? local = null;
    if (local == null)
        Console.WriteLine("empty");

    local = (v) => { Console.WriteLine($"lambda {v}"); };
    if (local != null)
        local(3);

    Notify sure = local!;
    sure(4);
    Notify? again = sure;
    Console.WriteLine($"{again == sure} {again == null}");

    Console.WriteLine(Apply(null, 1) + " " + Apply(Show, 2));

    Notify?[] handlers = [null, counter.Add, null];
    foreach (var handler in handlers)
    {
        if (handler is { } run)
            run(10);
    }
    Console.WriteLine($"{counter.Total}");
    return 0;
}
