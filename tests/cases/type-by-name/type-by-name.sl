// SPDX-License-Identifier: 0BSD
//
// Finding a type by its name, and building one from a document that names it.
//
// `typeof` resolves to a constant, which is what makes reflection free, and is
// also why it cannot serve a document that says which type it wants. This is
// the other half: every [Reflect] type in the binary is in a sorted table
// registered before Main runs, and `FindType` is a binary search over it.
//
// Together with the property table, that is enough to build an object graph
// from data -- which is what a form file is.
module TypeByName;

import Standard.Collections;
import Standard.Console;
import Standard.Convert;
import Standard.Reflection;

[Reflect]
public class Button
{
    public int Layouts;
    int _left;

    public Button()
    {
        Layouts = 0;
        _left = 0;
        Caption = "";
        Enabled = false;
    }

    public int Left
    {
        get => _left;
        set
        {
            _left = value;
            Layouts = Layouts + 1;
        }
    }

    public String Caption { get; set; }
    public bool Enabled { get; set; }
}

[Reflect]
public class Slider
{
    public Slider() => Value = 0.0;
    public double Value { get; set; }
}

/// A type with no [Reflect], to show it is not findable.
public class Hidden
{
    public int Anything;
    public Hidden() => Anything = 0;
}

void Say(String label, String value)
{
    Console.WriteLine(label + " = " + value);
}

/// One line of a very small form file: a type, a property and a value.
///
/// This is the whole point of the two features together -- nothing below
/// mentions Button or Slider by name in code.
byte* Build(String typeName, String[] settings)
{
    var type = FindType(typeName);
    if (!type.Exists)
        return null;

    byte* made = Make(type);
    if (made == null)
        return null;

    for (nuint i = 0u; i + 1u < settings.Length; i = i + 2u)
    {
        var property = type.FindProperty(settings[i]);
        if (!property.Exists || !property.CanWrite)
            continue;

        var value = settings[i + 1u];

        if (property.IsInteger)
        {
            var parsed = ToLong(value);
            if (parsed.Ok)
            {
                SetInteger(made, property, parsed.Value);
            }
        }
        else if (property.IsFloating)
        {
            var parsed = ToDouble(value);
            if (parsed.Ok)
            {
                SetDouble(made, property, parsed.Value);
            }
        }
        else if (property.IsText)
        {
            SetText(made, property, value);
        }
        else if (property.Kind == KindBool)
        {
            SetBool(made, property, value == "true");
        }
    }

    return made;
}

public int Main()
{
    // ------------------------------------------------------ finding a type
    var button = FindType("TypeByName.Button");
    Say("found", Text.FromBool(button.Exists));
    Say("name", button.Name);
    Say("properties", Text.FromInteger((long)button.PropertyCount));

    Say("qualified-needed", Text.FromBool(FindType("Button").Exists));
    Say("unreflected", Text.FromBool(FindType("TypeByName.Hidden").Exists));
    Say("nonsense", Text.FromBool(FindType("No.Such.Type").Exists));

    // A type in the standard library, to show the table is not just this file.
    Say("cross-module", Text.FromBool(FindType("TypeByName.Slider").Exists));

    // --------------------------------------------- building from a document
    var settings = new String[6];
    settings[0u] = "Left";
    settings[1u] = "40";
    settings[2u] = "Caption";
    settings[3u] = "OK";
    settings[4u] = "Enabled";
    settings[5u] = "true";

    byte* raw = Build("TypeByName.Button", settings);
    Say("built", Text.FromBool(raw != null));

    // Read it back through the same table.
    Say("left", Text.FromInteger(GetInteger(raw, button.FindProperty("Left"))));
    Say("caption", GetText(raw, button.FindProperty("Caption")));
    Say("enabled", Text.FromBool(GetBool(raw, button.FindProperty("Enabled"))));

    // The setter ran, which is the whole difference between this and writing
    // bytes: `Layouts` is counted by Left's setter and nothing else touches it.
    var counted = (Button)raw;
    Say("layouts", Text.FromInteger((long)counted.Layouts));
    Say("caption-direct", counted.Caption);

    var sliderSettings = new String[2];
    sliderSettings[0u] = "Value";
    sliderSettings[1u] = "2.5";

    byte* sliderRaw = Build("TypeByName.Slider", sliderSettings);
    var slider = (Slider)sliderRaw;
    Say("slider", Text.FromDouble(slider.Value));

    // A name nothing declares builds nothing rather than aborting.
    Say("unbuildable", Text.FromBool(Build("No.Such.Type", settings) != null));

    return 0;
}
