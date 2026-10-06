// SPDX-License-Identifier: 0BSD
//
// Everything an event refuses. An event is the one member whose whole point is
// what cannot be written to it.
module Bad;

public closure void Notify(int value);
public closure int Asked(int value);
public delegate void Plain(int value);

public interface IHasOne
{
    event Notify Wanted;                          // SLC0009: an interface has no state
}

public class Publisher
{
    public event Notify Fired;

    public event Asked Question;                  // SLC0118: handlers cannot return a value
    public event Plain Direct;                    // SLC0117: a delegate has no object
    public static event Notify Global;            // SLC0119: nothing would unsubscribe

    public void RaiseIt() => Fired(1); // fine: its own event, by name
}

public class Subscriber
{
    public void On(int value) { }
}

int Main()
{
    var p = new Publisher();
    var s = new Subscriber();

    p.Fired += s.On;                              // fine
    p.Fired -= s.On;                              // fine

    p.Fired(1);                                   // SLC0120: only Publisher may raise it
    Notify held = p.Fired;                        // SLC0121: an event has no value to read
    p.Fired = s.On;                               // SLC0122: '=' would replace the whole list
    p.Fired.Clear();                              // SLC0121: only Publisher may clear it

    return 0;
}
