module Main;

import Standard.Console;
import Standard.Text;
import Seam;

String Show(Colour c) {
    return Standard.Text.FromInteger((long)c.R) + " "
         + Standard.Text.FromInteger((long)c.G) + " "
         + Standard.Text.FromInteger((long)c.B) + " "
         + Standard.Text.FromInteger((long)c.A);
}

int Main() {
    Console.WriteLine("sizeof:    " + Standard.Text.FromInteger((long)sizeof(Colour)));
    Console.WriteLine("returned:  " + Show(Colour.Of(1, 2, 3)));

    var through = Pick(Colour.Of(10, 20, 30));
    if (through.Ok) {
        Console.WriteLine("through a variant: " + Show(through.Value));
    }

    var pair = Pair.Of(7, 9);
    Console.WriteLine("pair:      " + Standard.Text.FromInteger((long)pair.First)
        + " " + Standard.Text.FromInteger((long)pair.Second));
    return 0;
}
