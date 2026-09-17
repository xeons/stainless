// SPDX-License-Identifier: 0BSD
//
// Named attribute arguments, read back through reflection.
//
// An attribute's fields are positional in the order they were declared, and
// any of them may instead be set by name. What this case is really pinning is
// the third thing: a field written neither way still has a value — its type's
// default — so an attribute with six fields is not six values every use has to
// write out.
module NamedArguments;

import Standard.Console;
import Standard.Reflection;

/// A column in a table: the name it is stored under, how wide to print it, and
/// whether to print it at all.
public attribute Column
{
    String Name;
    int Width;
    bool Hidden;
}

[Reflect]
public class Row
{
    /// Positional, then named.
    [Column("full_name", Width = 32)]
    public String Name;

    /// Every field named, and one of them skipped.
    [Column(Name = "age", Hidden = true)]
    public int Years;

    /// Only the one field that has no sensible default.
    [Column("city")]
    public String City;

    /// All three positionally, which is what naming them is an alternative to.
    [Column("zip", 5, false)]
    public String Postcode;
}

/// A field nobody wrote a value for holds its type's default, and says so:
/// there is no value in the binary for it, so its kind is `KindNone`.
String Source(Attribute written, nuint index) =>
    written.ValueKind(index) == KindNone ? " (default)" : "";

int Main()
{
    var type = typeof(Row);

    for (nuint i = 0u; i < type.FieldCount; i++)
    {
        var field = type.FieldAt(i);
        var column = field.Get("Column");

        Console.WriteLine($"{field.Name}: {column.ValueCount} values, " +
                          $"name '{column.AsText(0u)}'{Source(column, 0u)}, " +
                          $"width {column.Number(1u)}{Source(column, 1u)}, " +
                          $"hidden {column.Number(2u)}{Source(column, 2u)}");
    }

    return 0;
}
