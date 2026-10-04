// A String constant is the immortal object a literal is; a char16* or char32*
// constant is zero-terminated UTF-16 or UTF-32, as C's u"..." and U"..." are.
module ConstStringKinds;

import Standard.Console;

public const String Greeting = "hello";
public const char16* Wide = "caf\U000000E9 \U0001F600";
public const char32* Wider = "caf\U000000E9 \U0001F600";

public sealed class Names
{
    public const String Default = "unnamed";
}

String Describe(String text = Names.Default) => $"'{text}', {text.ByteLength()} bytes";

nuint CountUnits16(char16* text)
{
    nuint count = 0;
    while (text[count] != 0)
        count++;
    return count;
}

nuint CountUnits32(char32* text)
{
    nuint count = 0;
    while (text[count] != 0)
        count++;
    return count;
}

int Main()
{
    Console.WriteLine(Describe(Greeting));
    Console.WriteLine($"a default: {Describe()}");
    Console.WriteLine($"equal to a literal: {Greeting == "hello"}, joined: {Greeting + ", world"}");
    Console.WriteLine($"in a type: {Names.Default}");

    switch ("hello")
    {
        case Greeting:
            Console.WriteLine("matched as a case");
            break;
        default:
            Console.WriteLine("not matched");
            break;
    }

    // Held, released, and held again many times: the object is never freed.
    nuint total = 0;
    for (int i = 0; i < 10000; i++)
    {
        String held = Greeting;
        total = total + held.ByteLength();
    }
    Console.WriteLine($"read ten thousand times: {total}");

    Console.WriteLine($"UTF-16: {CountUnits16(Wide)} units, e is {(int)Wide[3]:X4}, then {(int)Wide[5]:X4} {(int)Wide[6]:X4}");
    Console.WriteLine($"UTF-32: {CountUnits32(Wider)} units, e is {(int)Wider[3]:X4}, then {(int)Wider[5]:X5}");

    char16* again = Wide;
    Console.WriteLine($"the same address: {again == Wide}");
    return 0;
}
