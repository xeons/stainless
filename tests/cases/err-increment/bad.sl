// SPDX-License-Identifier: 0BSD
module Bad;

// `++` adds one to a number or steps a pointer. Everything else it could be
// asked of means something the spelling does not say.
public enum Level { Low, High }

public class Reading
{
    // No setter, so there is nowhere to write the answer back to.
    public int Value { get; }
    public Reading() => Value = 0;
}

int Main()
{
    // A choice is not a count.
    Level level = Level.Low;
    level++;

    // A read-only property has nothing to store into.
    var reading = new Reading();
    reading.Value++;

    // A literal is not a place.
    5++;

    // Neither is the result of a call.
    Answer()++;

    // A const is a place that was promised not to move.
    const int Fixed = 3;
    Fixed++;
    return 0;
}

int Answer() => 1;
