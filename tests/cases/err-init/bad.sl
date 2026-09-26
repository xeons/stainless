// SPDX-License-Identifier: 0BSD
//
// `init` is written while an object is being made and not after, and what
// stands in for an `init` accessor has to be one too.
module Bad;

public interface IHasId
{
    int Id { get; init; }
    int Rank { get; set; }
}

// Each disagrees with the interface about 'init'.
public class Mismatched : IHasId
{
    public int Id { get; set; }
    public int Rank { get; init; }
}

public class Base
{
    public virtual int Level { get; init; }
    public int Name { get; init; }
}

public class Derived : Base
{
    // An override may not trade 'init' for 'set'.
    public override int Level { get; set; }

    public Derived()
    {
        Name = 3;
    }

    // Not a constructor, so the object is already made.
    public void Rename()
    {
        Name = 5;
    }
}

public class Holder
{
    // A static belongs to no object that is being made.
    public static int Shared { get; init; }
}

int Main()
{
    var made = new Derived();
    made.Name = 7;
    return 0;
}
