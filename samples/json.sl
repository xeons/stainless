// SPDX-License-Identifier: 0BSD
module Json;

import Standard.Console;
import Standard.Reflection;

// Attributes are ordinary declarations. Their arguments must be constants,
// because the values are written into the binary alongside the field tables.
public attribute JsonName { String Name; }
public attribute JsonIgnore { }

// [Reflect] is what makes a type carry field metadata. Without it nothing is
// emitted and typeof is an error, so reflection costs nothing unless asked for.
[Reflect]
public class Person {
    [JsonName("full_name")] public String Name;
    [JsonName("age")]       public int    Years;
                            public bool   Active;
                            public double Rating;
    [JsonIgnore]            public int    Internal;
}

[Reflect]
public struct Point {
    public double X;
    public double Y;
}

// One serializer, written once, for any reflected type. T is concrete by the
// time this is compiled, so typeof(T) is a constant and every call below is a
// direct load from a table in .rdata.
public String ToJson<T>(T value) {
    var type = typeof(T);
    var text = new StringBuilder();

    text.Append("{");
    var first = true;

    for (nuint i = 0; i < type.FieldCount(); i = i + 1) {
        var field = type.FieldAt(i);
        if (field.Has("JsonIgnore")) { continue; }

        if (!first) { text.Append(","); }
        first = false;

        var name = field.Name();
        if (field.Has("JsonName")) { name = field.Get("JsonName").AsText(0); }

        text.Append("\"");
        text.Append(name);
        text.Append("\":");

        var raw = (byte*)value;
        if (field.Kind() == KindString) {
            text.Append("\"");
            text.Append(ReadText(raw, field));
            text.Append("\"");
        } else if (field.Kind() == KindBool) {
            text.Append(Text.FromBool(ReadBool(raw, field)));
        } else if (field.IsFloating()) {
            text.AppendDouble(ReadDouble(raw, field));
        } else if (field.IsInteger()) {
            text.AppendInteger(ReadInteger(raw, field));
        } else {
            text.Append("null");
        }
    }

    text.Append("}");
    return text.ToText();
}

int Main() {
    var person = new Person();
    person.Name = "Ada Lovelace";
    person.Years = 36;
    person.Active = true;
    person.Rating = 9.5;
    person.Internal = 999;

    Console.WriteLine(ToJson(person));

    // A struct works the same way, though it has no object header, so its
    // metadata is reached only through typeof.
    var type = typeof(Point);
    Console.WriteLine(type.Name() + " has " + Text.FromInteger(type.FieldCount())
                      + " fields, " + Text.FromInteger(type.Size()) + " bytes");
    return 0;
}
