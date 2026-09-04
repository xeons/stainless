// The consumer uses only what crossed. The case exists for what the library's
// build said about the rest.
module App;

import Standard.Console;
import Standard.Text;
import Warned;

int Main() {
    Point p;
    p.X = 1.5;
    p.Y = 2.0;

    var doubled = Doubled(p);
    Console.WriteLine("doubled: " + Text.FromDouble(doubled.X + doubled.Y));
    return 0;
}
