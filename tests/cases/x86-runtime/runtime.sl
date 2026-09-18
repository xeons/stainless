// The standard library on a target where a pointer is four bytes.
//
// Everything here reaches something the compiler and the runtime have to agree
// about the width of: an object header, an array's length, a string's byte
// count, a slice's offset. Each of those is a `size_t` in C and a `nuint` here,
// and before the target work one side of every pair was eight bytes and the
// other four -- which compiled, linked, ran, and gave the wrong number.
module X86Runtime;

import Standard.Console;
import Standard.Collections;
import Standard.Convert;

class Node
{
    public int Value { get; }
    public Node? Next { get; set; }

    public Node(int value)
    {
        Value = value;
        Next = null;
    }
}

int Main()
{
    // The two the layout actually turns on.
    Console.WriteLine("pointer   " + Text.FromInteger((long)sizeof(byte*)));
    Console.WriteLine("nuint     " + Text.FromInteger((long)sizeof(nuint)));

    // An array's length lives in its header, past three pointer-width words.
    var numbers = new int[5];
    for (nuint i = 0u; i < numbers.Length; i++)
        numbers[i] = (int)i * 11;
    Console.WriteLine("length    " + Text.FromInteger((long)numbers.Length));
    Console.WriteLine("last      " + Text.FromInteger((long)numbers[numbers.Length - 1]));

    // A slice carries an offset and a length of its own.
    var middle = numbers[1:4];
    Console.WriteLine("slice     " + Text.FromInteger((long)middle.Length)
                      + " " + Text.FromInteger((long)middle[0])
                      + " " + Text.FromInteger((long)middle[middle.Length - 1]));

    // A string's byte count sits where an array's length does.
    var text = "hello, " + "world";
    Console.WriteLine("bytes     " + Text.FromInteger((long)text.ByteLength()));
    Console.WriteLine("upper     " + text.ToUpperAscii());
    Console.WriteLine("found     " + Text.FromInteger(text.IndexOf("world")));

    // A class reference is a pointer, and its fields sit past the header.
    var head = new Node(1);
    var second = new Node(2);
    var third = new Node(3);
    head.Next = second;
    second.Next = third;

    // `is` with a binding, which asks about the null and the class at once and
    // reads the field exactly where it was checked -- a check on its own does
    // not narrow a field (SL0248).
    int total = head.Value;
    if (head.Next is Node one)
    {
        total += one.Value;
        if (one.Next is Node two)
            total += two.Value;
    }
    Console.WriteLine("chain     " + Text.FromInteger((long)total));

    // A generic over a hashed table: every probe is a `nuint`.
    var counts = new Dictionary<String, int>();
    counts.Set("one", 1);
    counts.Set("two", 2);
    counts.Set("three", 3);

    Console.WriteLine("entries   " + Text.FromInteger((long)counts.Count));
    if (counts.Find("two") is Some found)
    {
        Console.WriteLine("two       " + Text.FromInteger((long)found.Value));
    }

    // A list grows by doubling, which is arithmetic on lengths throughout.
    var names = new List<String>();
    names.Add("alpha");
    names.Add("beta");
    names.Add("gamma");
    Console.WriteLine("names     " + Text.FromInteger((long)names.Count)
                      + " " + names[2]);

    // And back out through the converter, which walks digits.
    var parsed = ToLong("4321");
    Console.WriteLine("parsed    " + Text.FromInteger(parsed.ValueOr(-1)));
    return 0;
}
