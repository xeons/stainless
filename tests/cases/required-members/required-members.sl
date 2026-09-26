// SPDX-License-Identifier: 0BSD
//
// A `required` member is one every `new` must give a value in its object
// initializer, unless the constructor it runs is marked `[SetsRequiredMembers]`.
// The check is at the `new`, so none of it costs anything at run time.
module RequiredMembers;

import Standard.Console;
import Standard.Text;
import Standard.Collections;

public class Node
{
    public String Name;

    public Node(String name)
    {
        Name = name;
    }

    ~Node()
    {
        Console.WriteLine("released " + Name);
    }
}

public class Person
{
    public required String Name { get; init; }
    public required int Age;
    public Node? Pet { get; set; }

    public Person() { }

    [SetsRequiredMembers]
    public Person(String name, int age)
    {
        Name = name;
        Age = age;
    }
}

/// Inherits both of its base's, and adds one.
public class Employee : Person
{
    public required Node Desk { get; set; }
}

public struct Size
{
    public required int Width;
    public int Height;

    public Size(int height)
    {
        Height = height;
    }
}

public class Labelled<T>
{
    public required T Value { get; init; }
    public String Label = "value";
}

String Describe(Person p) => p.Name + " " + Text.FromInteger(p.Age);

int Main()
{
    var ada = new Person { Name = "ada", Age = 36, Pet = new Node("cat") };
    Person bob = new() { Age = 40, Name = "bob" };
    var cy = new Person("cy", 5);
    Console.WriteLine(Describe(ada) + ", " + Describe(bob) + ", " + Describe(cy));

    var worker = new Employee { Name = "dee", Age = 30, Desk = new Node("desk") };
    Console.WriteLine(Describe(worker) + " at " + worker.Desk.Name);

    var size = new Size(2) { Width = 3 };
    Console.WriteLine(Text.FromInteger(size.Width * size.Height));

    var labelled = new Labelled<Node> { Value = new Node("held") };
    Console.WriteLine(labelled.Label + " " + labelled.Value.Name);

    var people = new List<Person> { new Person("ed", 1), new Person { Name = "fay", Age = 2 } };
    Console.WriteLine(Text.FromInteger((int)people.Count));
    return 0;
}
