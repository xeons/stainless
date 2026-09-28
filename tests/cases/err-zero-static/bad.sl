// An automatic static property with no `= value` would start as its type's
// zero, which a `String` does not have. One whose accessor only fills its
// storage with `field ??=` is read nowhere before it has a value.
module Bad;

public static class Settings
{
    public static String Name { get; set; }
    public static String Title { get => field ??= "untitled"; }
    public static int Count { get; set; }
}

int Main() => 0;
