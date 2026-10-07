// SPDX-License-Identifier: 0BSD
//
// A const is a constant expression: literals, constants, enum members, and the
// operators and casts between them, folded before the program runs. A
// constant may name one declared after it or in another module, and an enum
// member may name the members before it.
module ConstExpressions;

import Standard.Console;
import Standard.Text;
import Limits;

// Mach's spelling: a mask is a bit shifted into place.
public const uint MaskBadAccess = 1u << 1;
public const uint MaskBreakpoint = 1u << 6;
public const uint Masks = MaskBadAccess | MaskBreakpoint;

// Named before it is declared, and from another module.
public const int Doubled = Later * 2;
public const int Later = Limits.Most - 10;

// A narrowing cast wraps, as it does at run time; a flag in the top bit.
public const int ExceptionDefault64 = 1 | (int)0x80000000u;

public const long Big = (long)1 << 40;
public const nuint Page = 16u * 1024u;
public const byte Low = (byte)(0x1FF & 0xFF);
public const int Negative = -(Later / 3);
public const int Remainder = -7 % 3;
public const uint Inverted = ~0u >> 28;
public const int ArithmeticShift = -16 >> 2;
public const char Letter = 'A' + 2;
public const bool Wide = Big > 1000000 && !(Page == 0u);
public const int Chosen = Wide ? 3 : 4;
public const double Half = 1.0 / 2.0;
public const float Third = (float)(1.0 / 3.0);
public const String Greeting = "hello, " + "world";
public const Untyped = 3 * 7;

[Flags]
public enum Access : byte
{
    None = 0,
    Read = 1 << 0,
    Write = 1 << 1,
    ReadWrite = Read | Write,
    Execute = 1 << 2,
    All = Access.ReadWrite | Execute,
    Next,
}

public const Access Default = Access.Read | Access.Execute;

public struct Header
{
    public byte[Count * 2] Bytes;
}

public const int Count = 3;

public sealed class Sizes
{
    public const int Base = 8;
    public const int Twice = Base * 2;
}

int Main()
{
    Console.WriteLine("masks " + Text.FromInteger((long)Masks));
    Console.WriteLine("doubled " + Text.FromInteger(Doubled) + " later " + Text.FromInteger(Later));
    Console.WriteLine("default64 " + Text.FromInteger(ExceptionDefault64));
    Console.WriteLine("big " + Text.FromInteger(Big) + " page " + Text.FromInteger((long)Page));
    Console.WriteLine("low " + Text.FromInteger(Low) + " negative " + Text.FromInteger(Negative)
                      + " remainder " + Text.FromInteger(Remainder));
    Console.WriteLine("inverted " + Text.FromInteger((long)Inverted)
                      + " shifted " + Text.FromInteger(ArithmeticShift));
    Console.WriteLine("letter " + Text.FromInteger((long)Letter) + " wide " + (Wide ? "yes" : "no")
                      + " chosen " + Text.FromInteger(Chosen));
    Console.WriteLine("half " + Text.FromDouble(Half) + " third " + Text.FromDouble((double)Third));
    Console.WriteLine(Greeting + " " + Text.FromInteger(Untyped));
    Console.WriteLine("access " + Text.FromInteger((long)Access.ReadWrite) + " "
                      + Text.FromInteger((long)Access.All) + " " + Text.FromInteger((long)Access.Next)
                      + " default " + Text.FromInteger((long)Default));
    Header header = default;
    Console.WriteLine("header " + Text.FromInteger((long)header.Bytes.Length));
    Console.WriteLine("sizes " + Text.FromInteger(Sizes.Twice));

    // In a body, a constant is still the value folded for it.
    switch (5)
    {
        case Count + 2:
            Console.WriteLine("a case label folds too");
            break;
        default:
            Console.WriteLine("a case label did not fold");
            break;
    }

    switch (Default)
    {
        case Access.Read | Access.Execute:
            Console.WriteLine("and so does one of an enum's members combined");
            break;
        default:
            Console.WriteLine("an enum's case label did not fold");
            break;
    }

    // `&` binds tighter than `|` in a label too: 1 | (2 & 6) is 3.
    switch (3)
    {
        case 1 | 2 & 6:
            Console.WriteLine("and keeps the bitwise operators' precedence");
            break;
        default:
            Console.WriteLine("a label's operators bound in the wrong order");
            break;
    }
    return 0;
}
