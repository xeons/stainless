// SPDX-License-Identifier: 0BSD
//
// Multicast events: several subscribers, added and removed by value, raised in
// the order they subscribed.
module Events;

import Standard.Console;

public class Change
{
    public int Code;
    public Change(int code) => Code = code;
}

public closure void ChangeHandler(Source sender, Change what);

public class Source
{
    public String Name;

    public event ChangeHandler Changed;

    public Source(String name) => Name = name;

    // Only this type can raise its own event, and it does so by name.
    public void Announce(int code) => Changed(this, new Change(code));
}

public class Listener
{
    public String Tag;

    // Held so a handler can unsubscribe itself while the event is running.
    public Source? Watching;

    public Listener(String tag) => Tag = tag;

    public void OnChanged(Source sender, Change what)
    {
        Console.WriteLine(Tag + " " + sender.Name + " " + Text.FromInteger(what.Code));
    }

    public void Once(Source sender, Change what)
    {
        Console.WriteLine("once " + Text.FromInteger(what.Code));
        if (Watching is Source s)
            s.Changed -= this.Once;
    }
}

int Main()
{
    var source = new Source("s");

    // Nobody has subscribed. Raising is a no-op rather than a null to trip over.
    source.Announce(1);

    var a = new Listener("a");
    var b = new Listener("b");

    source.Changed += a.OnChanged;
    source.Changed += b.OnChanged;
    source.Announce(2);

    // Both words of a closure are compared, so this removes a's and leaves b's.
    source.Changed -= a.OnChanged;
    source.Announce(3);

    // The same handler twice is two subscriptions; one '-=' undoes one of them.
    source.Changed += b.OnChanged;
    source.Announce(4);
    source.Changed -= b.OnChanged;
    source.Announce(5);

    // Removing something that was never added is how a tidy-up runs twice.
    source.Changed -= a.OnChanged;
    source.Announce(6);

    // A lambda is a closure too.
    source.Changed += (sender, what) =>
    {
        Console.WriteLine("lambda " + Text.FromInteger(what.Code));
    };
    source.Announce(7);

    // A handler that unsubscribes while the event is being raised. The raise
    // took the subscriber list before it started, so everything that was
    // subscribed when it began still runs -- and the next raise sees the change.
    var other = new Source("t");
    var once = new Listener("c");
    once.Watching = other;

    other.Changed += once.Once;
    other.Changed += once.OnChanged;
    other.Announce(8);
    other.Announce(9);

    return 0;
}
