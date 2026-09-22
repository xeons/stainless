// SPDX-License-Identifier: 0BSD
//
// Reflection over properties: the accessors, rather than the storage behind
// them.
//
// The difference is the whole point. A field is an offset, so writing one
// stores bytes; a property is a pair of functions, so writing one runs the
// setter. For plain data the first is right and cheaper. For anything whose
// setter does work -- a control that re-lays-out when it moves -- only the
// second is correct, and until now reflection could not tell the two apart:
// an automatic property's storage is a field named after the property.
module Properties;

import Standard.Collections;
import Standard.Console;
import Standard.Reflection;

/// A type whose setters do something, which is how the test can tell which
/// path was taken.
[Reflect]
public class Control
{
    /// Counts every time a setter ran. A field, so reflection sees it as one.
    public int Layouts;

    int _left;
    String _name;

    public Control()
    {
        Layouts = 0;
        _left = 0;
        _name = "";
    }

    /// A hand-written property: no backing field, so nothing in the field
    /// table is named 'Left' at all.
    public int Left
    {
        get => _left;
        set
        {
            _left = value;
            Layouts = Layouts + 1;
        }
    }

    /// An automatic one. Its storage *is* a field named 'Name', which is the
    /// case that used to be indistinguishable.
    public String Name { get; set; }

    /// Read-only, so `CanWrite` is false and a loader can say so rather than
    /// silently dropping what a document asked for.
    public int Right { get { return _left + 10; } }

    public bool Visible { get; set; }
    public double Weight { get; set; }
}

/// Inheritance: a derived class lists what it inherited.
[Reflect]
public class Panel : Control
{
    public int Depth { get; set; }
    public Panel() => base();
}

void Say(String label, String value)
{
    Console.WriteLine(label + " = " + value);
}

String KindName(int kind)
{
    if (kind == KindInt)
        return "int";
    if (kind == KindString)
        return "String";
    if (kind == KindBool)
        return "bool";
    if (kind == KindDouble)
        return "double";
    return "kind " + Text.FromInteger((long)kind);
}

public int Main()
{
    var type = typeof(Control);

    // ------------------------------------------------------- what is listed
    Say("properties", Text.FromInteger((long)type.PropertyCount));

    var names = new StringBuilder();
    for (nuint i = 0u; i < type.PropertyCount; i = i + 1u)
    {
        var property = type.GetPropertyAt(i);
        if (i > 0u)
            names.Append(",");
        names.Append(property.Name);
        names.Append(":");
        names.Append(KindName(property.Kind));
        names.Append(property.CanRead ? "r" : "-");
        names.Append(property.CanWrite ? "w" : "-");
    }
    Say("listed", names.ToText());

    // A field named after an automatic property says so; one the type
    // declared does not.
    var fields = new StringBuilder();
    for (nuint i = 0u; i < type.FieldCount; i = i + 1u)
    {
        var field = type.GetFieldAt(i);
        if (i > 0u)
            fields.Append(",");
        fields.Append(field.Name);
        fields.Append(field.IsPropertyStorage ? "(property)" : "(field)");
    }
    Say("fields", fields.ToText());

    // ------------------------------------------------- the setter really runs
    var control = new Control();
    byte* raw = (byte*)control;

    var left = type.FindProperty("Left");
    SetInteger(raw, left, 42);
    SetInteger(raw, left, 7);

    Say("left", Text.FromInteger(GetInteger(raw, left)));

    // Two sets, so two layouts. Writing the storage would have counted none,
    // and `Left` has no storage to write in any case.
    Say("layouts", Text.FromInteger((long)control.Layouts));

    // Reading through the getter, which is not a field read: Right is
    // computed and has no storage anywhere.
    var right = type.FindProperty("Right");
    Say("right", Text.FromInteger(GetInteger(raw, right)));
    Say("right-writable", Text.FromBool(right.CanWrite));

    SetInteger(raw, right, 999);
    Say("right-after", Text.FromInteger(GetInteger(raw, right)));

    // ------------------------------------------------------- the other kinds
    var name = type.FindProperty("Name");
    SetText(raw, name, "panel one");
    Say("name", GetText(raw, name));
    Say("name-direct", control.Name);

    var visible = type.FindProperty("Visible");
    SetBool(raw, visible, true);
    Say("visible", Text.FromBool(GetBool(raw, visible)));

    var weight = type.FindProperty("Weight");
    SetDouble(raw, weight, 2.5);
    Say("weight", Text.FromDouble(GetDouble(raw, weight)));

    // ------------------------------------------------------------- narrowing
    // Set through the wrong reader: a double written to an int property does
    // nothing rather than writing four bytes of a double's bits.
    SetDouble(raw, left, 3.5);
    Say("left-after-double", Text.FromInteger(GetInteger(raw, left)));
    Say("double-of-int", Text.FromDouble(GetDouble(raw, left)));

    // ---------------------------------------------------------- a missing one
    var missing = type.FindProperty("Nope");
    Say("missing", Text.FromBool(missing.Exists));

    // ------------------------------------------------------------ inheritance
    var panelType = typeof(Panel);
    var inherited = new StringBuilder();
    for (nuint i = 0u; i < panelType.PropertyCount; i = i + 1u)
    {
        if (i > 0u)
            inherited.Append(",");
        inherited.Append(panelType.GetPropertyAt(i).Name);
    }
    Say("panel", inherited.ToText());

    var panel = new Panel();
    byte* panelRaw = (byte*)panel;
    SetInteger(panelRaw, panelType.FindProperty("Left"), 5);
    SetInteger(panelRaw, panelType.FindProperty("Depth"), 9);
    Say("panel-left", Text.FromInteger((long)panel.Left));
    Say("panel-depth", Text.FromInteger((long)panel.Depth));
    Say("panel-layouts", Text.FromInteger((long)panel.Layouts));

    return 0;
}
