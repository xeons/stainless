// SPDX-License-Identifier: 0BSD
//
// C#'s Color Color rule for a class: a property named for its own type
// leaves the type's statics reachable through that name, because a value of
// the type has no instance member of that name. An instance member through
// the same name is still the property's.
module ClassNamedLikeMember;

import Standard.Console;

public sealed class Key
{
    private int _bits;

    private Key(int bits)
    {
        _bits = bits;
    }

    public static Key Create(int bits) => new Key(bits);

    public static int DefaultBits => 256;

    public static int Largest = 4096;

    public const int Smallest = 128;

    public int Bits => _bits;
}

public sealed class Certificate
{
    private Key _key;

    public Certificate()
    {
        _key = Key.Create(Key.DefaultBits);
    }

    public Key Key => _key;

    public String Describe() =>
        $"{Key.Bits} of {Key.Smallest} to {Key.Largest}, made {Key.Create(512).Bits}";

    public static String DescribeStatically() => $"static {Key.Create(1024).Bits}";
}

public int Main()
{
    var certificate = new Certificate();
    Console.WriteLine(certificate.Describe());
    Console.WriteLine(Certificate.DescribeStatically());
    return 0;
}
