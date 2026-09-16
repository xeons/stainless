// SPDX-License-Identifier: 0BSD
module TypeConstants;

import Standard.Console;
import Standard.Text;

// A `const` inside a type. It is inlined at every use exactly as a module-level
// one is, so unlike a `static` it needs no moment at which to be initialized --
// which is what lets a type in a `--shared` library carry one.

public sealed class Packet
{
    public const nuint HeaderSize = 20u;
    const int Magic = 0x5041;

    // Named without the type in front of it inside the type's own members,
    // in an instance method and a static one alike.
    public nuint Payload(nuint total) => total - HeaderSize;

    public static bool Recognizes(int word) => word == Magic;
}

public struct Frame
{
    public const int Width = 8;

    public static int Area(int height) => Width * height;
}

public static class Limits
{
    public const int Retries = 3;
    public const double Timeout = 1.5;
    public const char Separator = ':';
    public const bool Verbose = false;
}

public enum Level { Low, High }

public class Signal
{
    // A const's initializer is a literal, so an enum-typed one is written as
    // the number its member has -- the same rule a module-level const keeps.
    public const Level Default = 1;
}

// A derived class sees what its base declared, and so does a caller naming it
// through the derived type.
public class Base
{
    public const int Kind = 42;
}

public sealed class Derived : Base
{
    public int Inherited() => Kind;
}

int Main()
{
    Console.WriteLine("header  = " + Text.FromInteger((long)Packet.HeaderSize));
    Console.WriteLine("payload = " + Text.FromInteger((long)new Packet().Payload(64u)));
    Console.WriteLine("magic   = " + (Packet.Recognizes(0x5041) ? "yes" : "no"));
    Console.WriteLine("area    = " + Text.FromInteger((long)Frame.Area(3)));
    Console.WriteLine("retries = " + Text.FromInteger((long)Limits.Retries));
    Console.WriteLine("timeout = " + Text.FromDouble(Limits.Timeout));
    Console.WriteLine("verbose = " + (Limits.Verbose ? "yes" : "no"));
    Console.WriteLine("default = " + (Signal.Default == Level.High ? "high" : "low"));
    Console.WriteLine("kind    = " + Text.FromInteger((long)Derived.Kind));
    Console.WriteLine("through = " + Text.FromInteger((long)new Derived().Inherited()));

    // A constant is a compile-time value, so it can label a case.
    switch (42)
    {
        case Base.Kind:
            Console.WriteLine("label   = matched");
            break;

        default:
            Console.WriteLine("label   = missed");
            break;
    }

    return 0;
}
