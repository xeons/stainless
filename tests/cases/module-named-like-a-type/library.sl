// A type the program's own module happens to share a name with. Inside this
// module, `Store` is the class; a module elsewhere called `Store` was never
// imported here and MUST NOT take the name from it.
module Library;

static class Store
{
    public static int Count = 7;
}

public enum Shade { Light, Dark }

public int ReadCount() => Store.Count;
