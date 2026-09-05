// `[a, b, c]`: an array written out.
//
// It has no type of its own, the way a lambda and a bare variant case name do
// not. What it becomes is decided by where it is going -- and, unlike those
// two, it can also be decided by its own elements, because elements are values
// and a lambda's body is not.
//
// The three targets are all here because they are three different emissions: a
// `T[]` allocates, a `T[N]` is a slot, and a `T[:]` goes through the array it
// is a view of.
module ArrayLiterals;
import Standard.Console;
import Standard.Text;

void Show(String[] items) {
    var line = new StringBuilder();
    for (nuint i = 0u; i < items.Length; i = i + 1u) {
        line.Append(items[i]);
        line.Append(" ");
    }
    Console.WriteLine(line.ToText());
}

int Sum(int[:] slice) {
    int total = 0;
    for (nuint i = 0u; i < slice.Length; i = i + 1u) { total = total + slice[i]; }
    return total;
}

public struct Point { public int X; public int Y; }

public class Thing {
    public int N;
    public Thing(int n) { N = n; }
    ~Thing() { Console.WriteLine("  gone " + Text.FromInteger((long)N)); }
}

/// Every element is stored the way an assignment into an element would store
/// it, so a literal of references retains each one -- and these two outlive
/// the locals that made them.
Thing[] Build() {
    var a = new Thing(1);
    var b = new Thing(2);
    return [a, b];
}

public void Main() {
    // Inferred from the elements.
    var numbers = [1, 2, 3, 4];
    Console.WriteLine("count " + Text.FromInteger((long)numbers.Length));
    Console.WriteLine("third " + Text.FromInteger((long)numbers[2]));

    // Widening across elements, as a ternary's arms do.
    var mixed = [1, 2L, 3];
    Console.WriteLine("mixed " + Text.FromInteger(mixed[1]));

    // From the declared type.
    String[] names = ["alpha", "beta", "gamma"];
    Show(names);

    // Straight into a parameter, with a trailing comma.
    Show(["one", "two",]);

    // An inline array, whose length has to match.
    int[3] fixed = [7, 8, 9];
    Console.WriteLine("inline " + Text.FromInteger((long)fixed[1]));

    // A slice, through the array it is a view of.
    Console.WriteLine("sum " + Text.FromInteger((long)Sum([10, 20, 30])));

    // Structs, stored inline.
    var points = new Point[2];
    points[0].X = 1;
    Point[] made = [points[0], points[1]];
    Console.WriteLine("points " + Text.FromInteger((long)made.Length));

    // References, each retained.
    var texts = ["kept", "also kept"];
    Console.WriteLine("first " + texts[0]);

    // Empty, with a type to go on.
    String[] none = [];
    Console.WriteLine("empty " + Text.FromInteger((long)none.Length));

    // Counted like anything else: the objects survive the locals that made
    // them, and die when the array does.
    Console.WriteLine("build:");
    {
        var things = Build();
        Console.WriteLine("  held " + Text.FromInteger((long)things[0].N)
                          + " " + Text.FromInteger((long)things[1].N));
        Console.WriteLine("  dropping:");
    }
    Console.WriteLine("  dropped");
}
