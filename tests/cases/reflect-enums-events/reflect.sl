// SPDX-License-Identifier: 0BSD
//
// Reflection over an enum property and over events: an enum is its integer to
// the accessors, its members and [Flags] are described, and a class lists its
// public events with their delegates, its base's first.
module ReflectEnums;

import Standard.Console;
import Standard.Reflection;
import Standard.Text;

public enum Side { None, Top, Fill = 5 }

[Flags]
public enum Edges { None = 0, Left = 1, Right = 2 }

public closure void Handler(Base sender);

[Reflect]
public class Base
{
    public Side Docked { get; set; }
    public Edges Anchored { get; set; }
    public event Handler Clicked;
    int Hidden { get; set; }
}

[Reflect]
public class Derived : Base
{
    public event Handler Changed;
}

int Main()
{
    var type = typeof(Derived);
    var docked = type.FindProperty("Docked");
    var sides = docked.PropertyType;
    Console.WriteLine("Docked kind " + Text.FromInteger(docked.Kind) + " enum " + (sides.IsEnum ? "yes " + sides.Name : "no"));
    for (nuint i = 0u; i < sides.EnumMemberCount; i++)
        Console.WriteLine("  " + sides.GetEnumMemberName(i) + " = " + Text.FromInteger(sides.GetEnumMemberValue(i)));
    var edges = type.FindProperty("Anchored").PropertyType;
    Console.WriteLine("Edges flags " + (edges.HasAttribute("Flags") ? "yes" : "no"));

    var made = new Derived();
    SetInteger((byte*)made, docked, 5L);
    Console.WriteLine("set Docked to Fill: " + (made.Docked == Side.Fill ? "yes" : "no"));
    Console.WriteLine("read back " + Text.FromInteger(GetInteger((byte*)made, docked)));

    Console.WriteLine("Docked public " + (docked.IsPublic ? "yes" : "no")
                      + ", Hidden public " + (type.FindProperty("Hidden").IsPublic ? "yes" : "no"));
    for (nuint i = 0u; i < type.EventCount; i++)
        Console.WriteLine("event " + type.GetEventAt(i).Name + " : " + type.GetEventAt(i).HandlerTypeName);
    return 0;
}
