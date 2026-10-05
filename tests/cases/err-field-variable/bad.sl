// SPDX-License-Identifier: 0BSD
module Bad;

// Inside an accessor `field` is the property's storage, so a variable of that
// name could never be read: each of these is refused.
public class Shape
{
    String? _name;

    public Shape() => _name = null;

    public String Name
    {
        get
        {
            var field = _name;
            return field ?? "";
        }
    }

    public int Length
    {
        get
        {
            foreach (var field in [1, 2])
                return field;
            return 0;
        }
    }

    public bool Named
    {
        get => _name is String field && field != "";
    }

    /// `@field` is the ordinary name, and is allowed.
    public String Spelled
    {
        get
        {
            var @field = _name;
            return @field ?? "";
        }
    }
}

int Main() => 0;
