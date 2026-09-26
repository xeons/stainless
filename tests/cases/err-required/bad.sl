// SPDX-License-Identifier: 0BSD
//
// A `required` member is one every `new` must set, so it has to be settable
// wherever the type can be made, and every construction has to set it.
module Bad;

public class Named
{
    public required String Name { get; init; }
    public required int Age;

    public Named() { }

    [SetsRequiredMembers]
    public Named(String name)
    {
        Name = name;
        Age = 0;
    }
}

public class Wrong
{
    // Nothing could set these.
    public required int Computed => 3;
    public static required int Shared { get; set; }

    // A public type's required member is set by code outside its module.
    required int _hidden;
}

T Make<T>() where T : new() => new T();

int Main()
{
    var fine = new Named("ada");
    var none = new Named();
    var half = new Named { Name = "x" };
    Named typed = new() { Age = 3 };
    var made = Make<Named>();
    return 0;
}
