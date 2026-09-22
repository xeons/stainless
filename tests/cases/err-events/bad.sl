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
    event Notify Wanted;                          // SL0300: an interface has no state
}

public class Publisher
{
    public event Notify Fired;

    public event Asked Question;                  // SL0549: handlers cannot return a value
    public event Plain Direct;                    // SL0548: a delegate has no object
    public static event Notify Global;            // SL0550: nothing would unsubscribe

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

    p.Fired(1);                                   // SL0554: only Publisher may raise it
    Notify held = p.Fired;                        // SL0555: an event has no value to read
    p.Fired = s.On;                               // SL0556: '=' would replace the whole list
    p.Fired.Clear();                              // SL0555: only Publisher may clear it

    return 0;
}
