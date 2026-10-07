// A [Reflect] enum is reached by typeof and by name, and a type that was not
// found answers that it has nothing rather than reading through null.
module ReflectByName;

import Standard.Console;
import Standard.Reflection;
import Standard.Text;

[Reflect]
public enum Key
{
    None = 0,
    Enter = 13,
    A = 65,
}

public struct Plain
{
    public int Value;
}

[Reflect]
public struct Holder
{
    public int Value;
    public String Label;
}

int Main()
{
    var key = typeof(Key);
    Console.WriteLine("typeof: " + key.Name + " enum " + (key.IsEnum ? "yes" : "no")
                      + " members " + Text.FromInteger((long)key.EnumMemberCount));
    var found = FindType("ReflectByName.Key");
    Console.WriteLine("by name: " + (found.Exists ? found.Name : "missing")
                      + " " + found.GetEnumMemberName(1u) + " = " + Text.FromInteger(found.GetEnumMemberValue(1u)));

    var missing = FindType("ReflectByName.Plain");
    Console.WriteLine("unreflected: exists " + (missing.Exists ? "yes" : "no")
                      + ", name '" + missing.Name + "'"
                      + ", enum " + (missing.IsEnum ? "yes" : "no")
                      + ", members " + Text.FromInteger((long)missing.EnumMemberCount)
                      + ", fields " + Text.FromInteger((long)missing.FieldCount)
                      + ", properties " + Text.FromInteger((long)missing.PropertyCount)
                      + ", events " + Text.FromInteger((long)missing.EventCount));
    var nothing = missing.FindProperty("Value");
    Console.WriteLine("its property: exists " + (nothing.Exists ? "yes" : "no")
                      + ", public " + (nothing.IsPublic ? "yes" : "no")
                      + ", readable " + (nothing.CanRead ? "yes" : "no"));

    // A field of the wrong kind is neither read nor written as a reference.
    Holder held;
    held.Value = 7;
    held.Label = "kept";
    var holder = typeof(Holder);
    var value = holder.FindField("Value");
    WriteAggregate((byte*)&held, value, null);
    Console.WriteLine("an int written as a reference: " + Text.FromInteger(held.Value)
                      + ", read as one: " + (ReadAggregate((byte*)&held, value) == null ? "null" : "not null"));
    return 0;
}
