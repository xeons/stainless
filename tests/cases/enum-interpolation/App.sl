// SPDX-License-Identifier: 0BSD
//
// An enum in an interpolation writes its member's name, as C#'s does: the
// name for a value one member has, the set flags of a [Flags] enum joined
// with ", ", and the number for a value no name covers. `ToText()` is the
// same text outside a string.
module App;

import Standard.Console;
import Palette;

enum Level { Low, High = 10 }

enum Temperature : sbyte { Cold = -1, Warm = 1 }

enum Twice { First = 1, Second = 1 }

enum Wide : ulong { Top = 0x8000000000000000 }

[Flags]
enum Style { Bold = 1, Italic = 2, Underline = 8 }

String Show<T>(T value) => $"<{value}>";

public int Main()
{
    // One member each.
    Console.WriteLine($"{Level.Low} {Level.High} {(Level)5}");
    Console.WriteLine($"{Temperature.Cold} {Temperature.Warm} {(Temperature)(-5)}");
    Console.WriteLine($"{Twice.Second} {Wide.Top} {(Wide)1}");

    // From another module, and nested in a class.
    Console.WriteLine($"{Colour.Blue} {Widget.State.Busy}");

    // Flags: a member's own name wins, and the rest is decomposed from the
    // largest member down and written smallest first.
    var access = Access.Read | Access.Execute;
    Console.WriteLine($"{Access.None} | {Access.Read | Access.Write} | {access}");
    Console.WriteLine($"{Access.Read | Access.Write | Access.Execute} | {(Access)16}");

    // Flags with no zero member, and a bit no member names.
    Console.WriteLine($"{(Style)0} | {Style.Bold | Style.Italic | Style.Underline}");
    Console.WriteLine($"{(Style)(1 | 4)}");

    // Outside an interpolation, aligned, and through a generic.
    String text = Level.High.ToText();
    Console.WriteLine($"{text} [{Colour.Red,6}] [{Colour.Green,-6}] {Show(Colour.Green)}");
    return 0;
}
