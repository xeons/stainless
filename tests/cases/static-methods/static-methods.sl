// SPDX-License-Identifier: 0BSD
//
// Static methods: members that belong to the type rather than to one of its
// values.
//
// The whole of the difference is the missing receiver. There is no `this`, so
// the body cannot reach a field, and a call names the type rather than a
// value. What that buys is a place to put a function that makes one of these:
// a constructor has to return its own type, so it cannot say why it failed,
// and before this the only place left for a fallible factory was a bare
// module function beside the type.
module StaticMethods;

import Standard.Console;
import Standard.Collections;

extern "C" int printf(byte* format, ...);

// -------------------------------------------------------- making the thing

public enum ParseError
{
    None,
    Empty,
    NotADigit,
    TooBig,
}

/// A number between 0 and 999, which not every string is.
///
/// The constructor is private and takes something already checked; `Parse` is
/// the way in, and it reports what was wrong. That pairing is the reason
/// static methods exist here.
public class Small
{
    int _value;

    Small(int checked) => _value = checked;

    public static Result<Small, ParseError> Parse(String text)
    {
        if (text.ByteLength() == 0u)
            return Fail(ParseError.Empty);

        int total = 0;
        for (nuint i = 0u; i < text.ByteLength(); i = i + 1u)
        {
            byte digit = text.GetByteAt(i);
            if (digit < (byte)'0' || digit > (byte)'9')
                return Fail(ParseError.NotADigit);

            total = total * 10 + (int)(digit - (byte)'0');
            if (total > 999)
                return Fail(ParseError.TooBig);
        }

        return Ok(new Small(total));
    }

    /// A second way in, for a number that is already known to fit.
    public static Small Of(int _value) => new Small(_value);

    public int Value => _value;

    /// A static method may call another, and may use the private constructor
    /// the whole point of this was to hide.
    public static Small Sum(Small left, Small right)
    {
        return Of(left.Value + right.Value);
    }
}

// ------------------------------------------------------------- on a struct

/// Structs have no constructors at all, so a static method is the only way to
/// make one in a single expression.
public struct Span
{
    public int Start;
    public int End;

    public static Span From(int start, int end)
    {
        Span made;
        made.Start = start;
        made.End = end;
        return made;
    }

    public static Span Empty() => From(0, 0);

    public int Length => End - Start;

    /// Static and instance members of one type share a name space, so this is
    /// an overload of `Length` and not a redeclaration of it.
    public static int Length(Span of) => of.End - of.Start;
}

// ------------------------------------------------------ reached as a value

public delegate int Combine(Small left, Small right);

int Total(Small[] values, Combine how)
{
    if (values.Length == 0u)
        return 0;

    var running = values[0];
    for (nuint i = 1u; i < values.Length; i = i + 1u)
    {
        running = Small.Of(how(running, values[i]));
    }
    return running.Value;
}

int Added(Small left, Small right) => left.Value + right.Value;

// ------------------------------------------------------------------- main

String Why(ParseError why)
{
    switch (why)
    {
        case ParseError.Empty: return "empty";
        case ParseError.NotADigit: return "not a digit";
        case ParseError.TooBig: return "too big";
        default: return "none";
    }
}

void Report(String text)
{
    var parsed = Small.Parse(text);
    if (parsed.Ok)
    {
        printf("%-8s -> %d\n", text.ToPointer(), parsed.Value.Value);
    }
    else
    {
        printf("%-8s -> %s\n", text.ToPointer(), Why(parsed.Error).ToPointer());
    }
}

public int Main()
{
    Report("0");
    Report("42");
    Report("999");
    Report("");
    Report("12x");
    Report("1000");

    // A static method calling a static method, through the private
    // constructor neither of them could reach from outside.
    printf("sum      = %d\n", Small.Sum(Small.Of(20), Small.Of(22)).Value);

    // On a struct, where there was no other way to build one in an
    // expression.
    var span = Span.From(3, 11);
    printf("span     = %d %d %d\n", span.Start, span.End, span.Length);
    printf("empty    = %d\n", Span.Empty().Length);

    // The overload that takes the value rather than being called on one.
    printf("overload = %d\n", Span.Length(span));

    // Named without being called, which makes it a delegate like any other
    // function name.
    var values = new Small[3];
    values[0] = Small.Of(1);
    values[1] = Small.Of(2);
    values[2] = Small.Of(3);
    printf("delegate = %d\n", Total(values, Added));

    return 0;
}
