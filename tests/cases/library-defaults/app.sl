// SPDX-License-Identifier: 0BSD
//
// The consumer has the library's metadata and no source. Every default below
// was written in a compilation this one never saw.
module App;

import Standard.Console;
import Standard.Text;
import Library.Paint;

int Main() {
    // The const the library folded, arriving as the number it was.
    var brush = new Brush("flat");
    Console.WriteLine(brush.Name + " " + Text.FromInteger(brush.Width));
    Console.WriteLine(Text.FromInteger(new Brush("fine", 2).Width));

    // A method's, including an enum member.
    Console.WriteLine(brush.Stroke());
    Console.WriteLine(brush.Stroke(9));
    Console.WriteLine(brush.Stroke(shade: Shade.Pale));

    // A String literal default, and one reached past by name.
    Console.WriteLine(Label("edge"));
    Console.WriteLine(Label("edge", ""));
    Console.WriteLine(Label("edge", upper: true));
    return 0;
}
