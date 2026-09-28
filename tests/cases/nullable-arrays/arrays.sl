// `T[]?`: an array reference that may be null, narrowed as `C?` is.
//
// The same one pointer as `T[]`, so the conversion in is free and the one
// out is a check the compiler has seen, or a cast.
module NullableArrays;

import Standard.Console;

public class Packet
{
    public byte[]? Payload;
    public String[]? Names = null;
}

nuint LengthOf(byte[]? data)
{
    if (data == null)
        return 0u;
    return data.Length;
}

int SumOf(int[]? values)
{
    int total = 0;
    if (values is { } present)
    {
        foreach (int value in present)
            total += value;
    }
    return total;
}

byte[]? Maybe(bool give) => give ? [9, 8, 7] : null;

int Main()
{
    byte[]? none = null;
    byte[]? some = [1, 2, 3];
    Console.WriteLine($"{LengthOf(none)} {LengthOf(some)}");
    Console.WriteLine($"{SumOf(null)} {SumOf([4, 5, 6])}");

    var packet = new Packet();
    Console.WriteLine($"{packet.Payload == null} {packet.Names == null}");

    packet.Payload = [4, 5];
    if (packet.Payload is { } bytes)
        Console.WriteLine($"{bytes.Length} {bytes[1]}");

    packet.Names = ["a", "b"];
    String[] names = packet.Names!;
    Console.WriteLine(names[0] + names[1]);

    byte[] sure = (byte[])Maybe(true);
    Console.WriteLine($"{sure[0]}");

    byte[]? missing = Maybe(false);
    Console.WriteLine($"{missing == null} {missing != null}");

    byte[] whole = [1];
    byte[]? held = whole;
    Console.WriteLine($"{held == whole}");
    return 0;
}
