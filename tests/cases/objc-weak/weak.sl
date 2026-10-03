// Weak references to Objective-C objects, which are boxes holding the
// runtime's own weak slot: a local, a field, a copy sharing the box, and the
// weak `this` a subscribed lambda holds -- so an Objective-C object that
// subscribes to an event is not kept alive by it, and its handler does
// nothing once it has gone. An event declared on an Objective-C class is
// given its subscriber list as the runtime allocates the object.
module ObjCWeak;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("alloc")] public static Self Alloc();
    [Selector("init")] public Self Init();
}

public closure void Notify(long value);

public class Publisher
{
    public event Notify Fired;
    public void Raise(long value) => Fired(value);
}

public objc class Listener : NSObject
{
    public static int Alive = 0;
    public static long Heard = 0;

    long _scale = 1;

    public Listener(long scale)
    {
        _scale = scale;
        Alive++;
    }

    // Calls a method of this object, so the lambda holds `this`, weakly.
    public void Listen(Publisher publisher) =>
        publisher.Fired += (long value) => Hear(value);

    void Hear(long value) => Heard += value * _scale;

    ~Listener()
    {
        Alive--;
    }
}

public class Tally
{
    public long Total;
}

public objc class Source : NSObject
{
    public event Notify Changed;
    public void Change(long value) => Changed(value);
}

public class Holder
{
    public weak Listener? Held;
}

void Locals()
{
    weak Listener? loose;
    var copy = loose;
    {
        var listener = new Listener(2);
        loose = listener;
        copy = loose;
        Console.WriteLine($"while held: {loose is not null} {copy is not null}, alive {Listener.Alive}");
    }
    Console.WriteLine($"once released: {loose is null} {copy is null}, alive {Listener.Alive}");
}

void Fields()
{
    var holder = new Holder();
    var listener = new Listener(3);
    holder.Held = listener;
    Listener? read = holder.Held;
    Console.WriteLine($"field holds it: {read is not null}");
    read = null;
    listener = new Listener(4);
    Console.WriteLine($"field after the last strong reference went: {holder.Held is null}, alive {Listener.Alive}");
}

void Subscriptions()
{
    var publisher = new Publisher();
    {
        var listener = new Listener(10);
        listener.Listen(publisher);
        publisher.Raise(1);
        Console.WriteLine($"heard while alive: {Listener.Heard}");
    }
    publisher.Raise(5);
    Console.WriteLine($"heard after it went: {Listener.Heard}, alive {Listener.Alive}");
}

void Events()
{
    var source = new Source();
    var tally = new Tally();
    source.Changed += (long value) => tally.Total += value;
    source.Changed += (long value) => tally.Total += value * 100;
    source.Change(2);
    Console.WriteLine($"an Objective-C class's event: {tally.Total}");
}

int Main()
{
    WithAutoreleasePool(() => Locals());
    WithAutoreleasePool(() => Fields());
    WithAutoreleasePool(() => Subscriptions());
    WithAutoreleasePool(() => Events());
    Console.WriteLine($"alive at the end: {Listener.Alive}");
    return 0;
}
