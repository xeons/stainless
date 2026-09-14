// SPDX-License-Identifier: 0BSD
//
// A default is filled in at the call site, from the declaration the caller can
// see. That is the whole of the feature and the reason for every rule around
// it: the value has to be a constant, because it is written into the call
// rather than run at the callee; and only one declaration may give it, because
// two would mean the same line meant different things.
module DefaultArguments;

import Standard.Console;
import Standard.Text;

public const int Wide = 12;

public enum Level { Quiet, Loud }

public class Box {
    public int Width;
    public String Label;

    public Box(String label, int width = Wide) {
        Label = label;
        Width = width;
    }
}

public interface IRender {
    String Render(int width = 3);
}

/// A class implementing it does not restate the default: there is one
/// declaration a call can read, and this is it.
public class Bar : IRender {
    public String Render(int width) {
        return "#".Repeat((nuint)width);
    }
}

String Draw(String text, int width = 8, char fill = '.', bool loud = false) {
    String body = text;

    while ((int)body.ByteLength() < width)
        body = body + $"{(char32)fill}";

    if (loud)
        return body.ToUpperAscii();

    return body;
}

String Greet(String who, String greeting = "hello", Level level = Level.Quiet) {
    return greeting + " " + who + " " + Text.FromInteger((int)level);
}

/// Null is a constant too, and it is the one a reference parameter wants.
String NameOf(Box? box = null) {
    return box?.Label ?? "nothing";
}

int Main() {
    // Left off from the right, one at a time.
    Console.WriteLine(Draw("ab"));
    Console.WriteLine(Draw("ab", 4));
    Console.WriteLine(Draw("ab", 4, '-'));
    Console.WriteLine(Draw("ab", 4, '-', true));

    // A name reaches past one that was left out, which is what names are for.
    Console.WriteLine(Draw("ab", loud: true));
    Console.WriteLine(Draw("ab", fill: '*', width: 5));

    // A const and an enum member are constants, and so may be defaults.
    Console.WriteLine(Greet("world"));
    Console.WriteLine(Greet("world", "hi", Level.Loud));
    Console.WriteLine(Greet("world", greeting: "hey"));

    var box = new Box("crate");
    Console.WriteLine(box.Label + " " + Text.FromInteger(box.Width));
    Console.WriteLine(Text.FromInteger(new Box("tin", 3).Width));

    Console.WriteLine(NameOf());
    Console.WriteLine(NameOf(box));

    // Through the interface, where the default is declared.
    IRender bar = new Bar();
    Console.WriteLine(bar.Render());
    Console.WriteLine(bar.Render(6));
    return 0;
}
