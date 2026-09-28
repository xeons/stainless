// SPDX-License-Identifier: 0BSD
//
// Reflection makes an object only as `new` would, and never hands out one
// with a null where its type says there is none (§2.16).
module ReflectZero;

import Standard.Console;
import Standard.Reflection;

void Say(String label, String value)
{
    Console.WriteLine(label + " = " + value);
}

String Answer(bool value) => value ? "yes" : "no";

[Reflect]
public class Counter
{
    public int Count;
}

[Reflect]
public class Named
{
    public String Name;
    public String? Nick;
    public String[] Tags;
    public int[]? Counts;

    public Named()
    {
        Name = "from the constructor";
        Tags = ["a"];
    }

    public String Title { get; set; } = "untitled";
}

[Reflect]
public class Argued
{
    public String Name;
    public Argued(String name) => Name = name;
}

[Reflect]
public abstract class Shape
{
    public int Sides;
}

[Reflect]
public struct Point
{
    public int X;
    public int Y;
}

[Reflect]
public class Ticket
{
    public required String Code;
    public required int Seat;
}

public closure void Rung(int times);

[Reflect]
public class Bell
{
    public event Rung Rang;
    public void Ring() => Rang(1);
}

public class Listener
{
    public int Heard;
    public Listener() => Heard = 0;
    public void OnRang(int times) => Heard += times;
}

[Reflect]
public struct Pair
{
    public String Left;
    public String Right;
}

[Reflect]
public class Holder
{
    public Named Named;
    public Named? Maybe;
    public String[]? Words;
    public Named[]? Group;
    public Pair[]? Pairs;
    public int[]? Numbers;

    public Holder() => Named = new Named();
}

bool WriteCode(byte* made)
{
    WriteText(made, typeof(Ticket).FindField("Code"), "A-1");
    return true;
}

bool LeaveCode(byte* made) => true;

bool RefuseAnyway(byte* made)
{
    WriteText(made, typeof(Ticket).FindField("Code"), "B-2");
    return false;
}

public int Main()
{
    // --------------------------------------------------------- the metadata
    var named = typeof(Named);
    Field name = named.FindField("Name");
    Field nick = named.FindField("Nick");
    Field tags = named.FindField("Tags");
    Field counts = named.FindField("Counts");
    Say("name", Answer(name.HasZeroValue) + "/" + Answer(name.IsNullable));
    Say("nick", Answer(nick.HasZeroValue) + "/" + Answer(nick.IsNullable));
    Say("tags", Answer(tags.HasZeroValue) + "/" + Answer(tags.ElementHasZeroValue));
    Say("counts", Answer(counts.IsNullable) + "/" + Answer(counts.ElementHasZeroValue));
    Say("code-required", Answer(typeof(Ticket).FindField("Code").IsRequired));
    Say("title-property", Answer(named.FindProperty("Title").HasZeroValue));

    // ------------------------------------------------------ what can be made
    Say("counter", Answer(typeof(Counter).CanCreateInstance));
    Say("named", Answer(named.CanCreateInstance));
    Say("argued", Answer(typeof(Argued).CanCreateInstance));
    Say("abstract", Answer(typeof(Shape).CanCreateInstance));
    Say("struct", Answer(typeof(Point).CanCreateInstance));
    Say("argued-made", Answer(CreateInstance(typeof(Argued)) != null));
    Say("struct-made", Answer(CreateInstance(typeof(Point)) != null));

    // The constructor ran, so every field it writes holds its value.
    var holder = new Holder();
    Field maybe = typeof(Holder).FindField("Maybe");
    byte* inner = CreateInstanceInto((byte*)holder, maybe);
    Say("made-into", Answer(inner != null && holder.Maybe != null));
    var made = (Named)holder.Maybe!;
    Say("made-name", made.Name);
    Say("made-title", made.Title);
    Say("made-tags", Text.FromInteger((long)made.Tags.Length));

    // An event's list is made as `new` makes it.
    byte* rawBell = CreateInstance(typeof(Bell));
    var madeBell = (Bell)rawBell;
    madeBell.Ring();
    var listener = new Listener();
    madeBell.Rang += listener.OnRang;
    madeBell.Ring();
    Say("rung", Text.FromInteger((long)listener.Heard));

    // ------------------------------------------------------ required members
    var ticket = typeof(Ticket);
    Say("ticket-plain", Answer(CreateInstance(ticket) != null));
    Say("ticket-left", Answer(CreateInstance(ticket, LeaveCode) != null));
    Say("ticket-refused", Answer(CreateInstance(ticket, RefuseAnyway) != null));
    byte* written = CreateInstance(ticket, WriteCode);
    Say("ticket-filled", written == null ? "null" : ((Ticket)written).Code);

    // ---------------------------------------------------------- the writers
    Field held = typeof(Holder).FindField("Named");
    WriteAggregate((byte*)holder, held, null);
    Say("null-refused", holder.Named.Name);
    WriteAggregate((byte*)holder, maybe, null);
    Say("null-allowed", Answer(holder.Maybe == null));
    SetAggregate((byte*)made, named.FindProperty("Title"), null);
    Say("setter-refused", made.Title);

    // ---------------------------------------------------------------- arrays
    Field words = typeof(Holder).FindField("Words");
    Say("words-plain", Answer(CreateArrayInto((byte*)holder, words, 2u) != null));
    Say("words-partial", Answer(CreateArrayInto((byte*)holder, words, 2u,
        (byte* array) =>
        {
            WriteTextAt(GetElementAddress(array, words, 0u), "one");
            return true;
        }) != null));
    Say("words-after", Answer(holder.Words == null));
    Say("words-full", Answer(CreateArrayInto((byte*)holder, words, 2u,
        (byte* array) =>
        {
            WriteTextAt(GetElementAddress(array, words, 0u), "one");
            WriteTextAt(GetElementAddress(array, words, 1u), "two");
            return true;
        }) != null));
    Say("words", holder.Words![0u] + " " + holder.Words![1u]);

    Field group = typeof(Holder).FindField("Group");
    Say("group", Answer(CreateArrayInto((byte*)holder, group, 1u,
        (byte* array) => CreateElementAt(GetElementAddress(array, group, 0u), group,
            (byte* element) => true) != null) != null));
    Say("group-name", holder.Group![0u].Name);

    Field pairs = typeof(Holder).FindField("Pairs");
    Field left = typeof(Pair).FindField("Left");
    Say("pairs-half", Answer(CreateArrayInto((byte*)holder, pairs, 1u,
        (byte* array) =>
        {
            WriteText(GetElementAddress(array, pairs, 0u), left, "left");
            return true;
        }) != null));

    Field numbers = typeof(Holder).FindField("Numbers");
    Say("numbers", Answer(CreateArrayInto((byte*)holder, numbers, 3u) != null));
    Say("numbers-length", Text.FromInteger((long)holder.Numbers!.Length));

    return 0;
}
