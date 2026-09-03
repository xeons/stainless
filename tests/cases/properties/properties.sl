// SPDX-License-Identifier: 0BSD
module Properties;

import Standard.Collections;
import Standard.Console;

extern "C" int printf(byte* format, ...);

// An interface may declare a property. Each accessor is one vtable slot, so a
// property dispatches exactly the way a method does.
public interface INamed {
    String Name { get; }
    int Rank { get; set; }
}

public class Person : INamed {
    // Automatic: the compiler supplies the storage and both accessors.
    public String Name { get; set; }
    public int Rank { get; set; }

    // Readable everywhere, writable only inside this module.
    public int Visits { get; private set; }

    // Get-only, so nothing but a constructor of this class may fill it in.
    public int Id { get; }

    // Computed: no storage of its own, and the arrow is the whole getter.
    public String Label => Name + "#" + Text.FromInteger(Id);

    public Person(String name, int id) {
        Name = name;
        Id = id;              // a get-only property, written by its constructor
        Rank = 1;
        Visits = 0;
    }

    ~Person() { printf("~Person(%s)\n", Name.ToPointer()); }

    public void Visit() { Visits = Visits + 1; }
}

// A property may compute over real fields, and either accessor may have a body.
public class Thermostat {
    int celsius;

    public Thermostat(int c) { celsius = c; }

    public int Celsius {
        get { return celsius; }
        set { celsius = value; }
    }

    public int Fahrenheit {
        get { return celsius * 9 / 5 + 32; }
        set { celsius = (value - 32) * 5 / 9; }
    }

    // Arrow bodies on both sides of a property.
    public int Kelvin {
        get => celsius + 273;
        set => celsius = value - 273;
    }
}

// Structs have properties too; the accessors take the receiver by pointer, the
// same way a struct method does.
public struct Rect {
    public int Width { get; set; }
    public int Height { get; set; }

    public int Area => Width * Height;
}

// A generic interface may declare a property, and a generic class implement it.
// Both are monomorphized, so the accessors land in a vtable like any other.
public interface IBox<T> { T Item { get; set; } }

public class Cell<T> : IBox<T> {
    public T Value { get; set; }
    public T Item { get; set; }
    public Cell(T initial) { Value = initial; Item = initial; }
}

class Tag {
    public String Text { get; }
    public Tag(String t) { Text = t; }
    ~Tag() { printf("~Tag(%s)\n", Text.ToPointer()); }
}

// A property holding a reference owns it: the setter releases what was there.
class Slot {
    public Tag Held { get; set; }
    public Slot(Tag first) { Held = first; }
    ~Slot() { printf("~Slot\n"); }
}

public delegate int Adjust(int value);
public interface IProduce { int Produce(); }

int Twice(int value) { return value * 2; }

// A property may hold a delegate, and calling through it is a call, not a
// dispatch — the property is read first, then the function pointer invoked.
class Policy {
    public Adjust Rule { get; set; }
    public Policy(Adjust rule) { Rule = rule; }

    // Unqualified, so the property is read through the implicit `this` and the
    // function pointer it holds is then called.
    public int Apply(int value) { return Rule(value); }
}

void Report(INamed named) {
    printf("dispatch name=%s rank=%d\n", named.Name.ToPointer(), named.Rank);
}

int Main() {
    var person = new Person("Ada", 7);

    printf("name=%s id=%d rank=%d\n", person.Name.ToPointer(), person.Id, person.Rank);
    printf("label=%s\n", person.Label.ToPointer());

    // A setter is a method call, and a property write is still an expression.
    person.Name = "Grace";
    person.Rank = 4;
    printf("renamed=%s rank=%d\n", person.Name.ToPointer(), person.Rank);

    // Compound assignment reads the getter and writes the setter.
    person.Rank += 6;
    person.Rank *= 2;
    printf("compound=%d\n", person.Rank);

    // A private setter is still writable from inside the declaring module.
    person.Visit();
    person.Visit();
    printf("visits=%d\n", person.Visits);

    // Through the interface, both accessors dispatch.
    INamed named = person;
    named.Rank = 42;
    Report(named);

    var thermostat = new Thermostat(100);
    printf("c=%d f=%d k=%d\n",
        thermostat.Celsius, thermostat.Fahrenheit, thermostat.Kelvin);

    thermostat.Fahrenheit = 212;
    printf("after f=212: c=%d\n", thermostat.Celsius);

    thermostat.Kelvin = 300;
    printf("after k=300: c=%d\n", thermostat.Celsius);

    // A struct property writes back into the variable it was read from.
    Rect rect;
    rect.Width = 3;
    rect.Height = 4;
    rect.Width += 2;
    printf("rect=%dx%d area=%d\n", rect.Width, rect.Height, rect.Area);

    // The property is the type's own name for its storage, so a generic one
    // works the way any other member of a generic does.
    var number = new Cell<int>(5);
    number.Value = number.Value * 3;

    var text = new Cell<String>("boxed");
    printf("cell=%d text=%s\n", number.Value, text.Value.ToPointer());

    IBox<int> boxed = number;
    boxed.Item = boxed.Item + 1;
    printf("boxed=%d\n", boxed.Item);

    var people = new List<Person>();
    people.Add(person);
    printf("held=%d first=%s\n", (int)people.Count(), people.At(0).Label.ToPointer());

    // A property write is an expression, so its value is what was stored and a
    // chain assigns both.
    var left = new Cell<int>(0);
    var right = new Cell<int>(0);
    left.Value = right.Value = 9;
    printf("chained=%d %d\n", left.Value, right.Value);

    // A reference-typed property owns what it holds: the setter releases the
    // old value, so the first tag dies at the assignment and not at the end.
    {
        var slot = new Slot(new Tag("first"));
        printf("replacing\n");
        slot.Held = new Tag("second");
        printf("replaced=%s\n", slot.Held.Text.ToPointer());
    }
    printf("scope left\n");

    var policy = new Policy(Twice);
    printf("delegate=%d %d\n", policy.Rule(21), policy.Apply(10));

    // The closure captured the reference by value, and the property is read
    // when it runs; so this sees 100, not the 42 that was there when it was made.
    IProduce produce = () => person.Rank + 1;
    person.Rank = 100;
    printf("closure=%d\n", produce.Produce());

    printf("done\n");
    return 0;
}
