// SPDX-License-Identifier: 0BSD
//
// A library that publishes an event. Three things have to cross for a consumer
// to subscribe: the closure type, the two methods '+=' and '-=' lower to, and
// the storage behind them. The third method -- the one that raises it -- is
// private and deliberately does not.
module Library.Bus;

import Standard.Console;

public closure void Reading(Sensor sender, int value);

public class Sensor
{
    public String Name;

    public event Reading Read;

    public Sensor(String name) => Name = name;

    // Only this type can raise its own event, wherever the subscribers are.
    public void Measure(int value) => Read(this, value);

    // What a consumer's handler runs alongside.
    public void Announce() => Console.WriteLine("measuring " + Name);
}
