// SPDX-License-Identifier: 0BSD
//
// The consumer. It subscribes to an event declared in a compilation it never
// saw, with handlers of its own, and the library raises them.
module App;

import Standard.Console;
import Library.Bus;

public class Log
{
    public String Tag;

    public Log(String tag) => Tag = tag;

    public void OnRead(Sensor sender, int value)
    {
        Console.WriteLine(Tag + " " + sender.Name + " " + Text.FromInteger(value));
    }
}

static int s_monitorsFreed = 0;

/// Owns a sensor from the library and subscribes itself to it, which holds it
/// weakly across the boundary as it does within one compilation.
public class Monitor
{
    Sensor _sensor;

    public Monitor()
    {
        _sensor = new Sensor("m");
        _sensor.Read += this.OnRead;
    }

    ~Monitor() { s_monitorsFreed++; }

    public void Take(int value) => _sensor.Measure(value);

    public void StopListening() { _sensor.Read -= this.OnRead; }

    public void OnRead(Sensor sender, int value)
    {
        Console.WriteLine("monitor " + Text.FromInteger(value));
    }
}

void WatchBriefly()
{
    var monitor = new Monitor();
    monitor.Take(6);
    monitor.StopListening();
    monitor.Take(7);
}

int Main()
{
    var sensor = new Sensor("s");

    // Allocated here, through the library's TypeInfo, and its event is empty
    // rather than absent -- so raising it with nobody subscribed does nothing.
    sensor.Announce();
    sensor.Measure(1);

    var a = new Log("a");
    var b = new Log("b");

    sensor.Read += a.OnRead;
    sensor.Read += b.OnRead;
    sensor.Measure(2);

    // Closure equality reaches across the boundary too: both words, so this
    // takes a's off and leaves b's.
    sensor.Read -= a.OnRead;
    sensor.Measure(3);

    // A lambda written here, subscribed to an event declared there.
    sensor.Read += (sender, value) =>
    {
        Console.WriteLine("lambda " + Text.FromInteger(value));
    };
    sensor.Measure(4);

    sensor.Read -= b.OnRead;
    sensor.Measure(5);

    WatchBriefly();
    var owned = new Monitor();
    owned.Take(8);
    owned = new Monitor();
    Console.WriteLine("monitors freed " + Text.FromInteger((long)s_monitorsFreed));

    return 0;
}
