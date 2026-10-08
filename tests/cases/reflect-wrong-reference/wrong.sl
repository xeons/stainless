// SPDX-License-Identifier: 0BSD
//
// Reflection's reference setters take untyped arguments, so they check what
// they store: a String only where a String goes, and an object in a class
// slot only when it is that class or derives from it. Anything else is
// refused and the slot keeps what it had.
module ReflectWrongReference;

import Standard.Console;
import Standard.Reflection;

[Reflect]
public class Engine
{
    public int Power;
    public Engine(int power) => Power = power;
}

[Reflect]
public class Turbo : Engine
{
    public Turbo() => base(500);
}

[Reflect]
public class Car
{
    public String Label { get; set; } = "plain";
    public Engine Motor { get; set; } = new Engine(100);
    public Engine Spare = new Engine(50);
}

int Main()
{
    var car = new Car();
    byte* raw = (byte*)car;
    var type = typeof(Car);

    // A String into a class property.
    SetText(raw, type.FindProperty("Motor"), "not an engine");
    Console.WriteLine($"motor {car.Motor.Power}");

    // An object into a String property.
    SetAggregate(raw, type.FindProperty("Label"), (byte*)new Engine(1));
    Console.WriteLine($"label {car.Label}");

    // An unrelated object into a class field.
    WriteAggregate(raw, type.FindField("Spare"), (byte*)car);
    Console.WriteLine($"spare {car.Spare.Power}");

    // What does fit still goes in: a String, and a derived class.
    SetText(raw, type.FindProperty("Label"), "fast");
    SetAggregate(raw, type.FindProperty("Motor"), (byte*)new Turbo());
    Console.WriteLine($"label {car.Label}, motor {car.Motor.Power}");
    return 0;
}
