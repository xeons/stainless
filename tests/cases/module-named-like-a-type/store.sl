module Store;

import Standard.Console;
import Library;

public int Main()
{
    Console.WriteLine($"count {ReadCount()}");
    Console.WriteLine($"shade {(int)Shade.Dark}");
    return 0;
}
