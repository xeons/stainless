// SPDX-License-Identifier: 0BSD
module ConstraintKinds;

import Standard.Console;

public struct Pixel
{
    public byte R;
    public byte G;
    public byte B;

    public Pixel(byte r, byte g, byte b)
    {
        R = r;
        G = g;
        B = b;
    }
}

public enum Level : byte { Low, High }

// Its bytes are the whole of it, so copying them is copying it.
void CopyBytes<T>(T* to, T* from, nuint count) where T : unmanaged
{
    var target = (byte*)to;
    var source = (byte*)from;
    for (nuint i = 0; i < count * sizeof(T); i++)
        target[i] = source[i];
}

nuint SizeOf<T>(T value) where T : unmanaged => sizeof(T);

public class Label
{
    public String Text;

    public Label(String text) => Text = text;
    ~Label() { Console.WriteLine("~Label " + Text); }
}

// None of its values is null, so a lookup can answer with one directly.
public class Registry<TKey, TValue> where TKey : notnull where TValue : notnull
{
    TKey[] _keys = new TKey[4];
    TValue[] _values = new TValue[4];
    nuint _count;

    public void Add(TKey key, TValue value)
    {
        _keys[_count] = key;
        _values[_count] = value;
        _count++;
    }

    public TValue At(nuint index) => _values[index];
    public TKey KeyAt(nuint index) => _keys[index];
}

public class Base
{
    public virtual String Name => "base";
}

public class Derived : Base
{
    public override String Name => "derived";
}

// The kind comes first and the rest follow it, in one clause per parameter.
String Describe<T, U>(T first, U second) where T : class, U where U : Base =>
    first.Name + "/" + second.Name;

int Main()
{
    int[] numbers = [1, 2, 3];
    int[] copy = new int[3];
    CopyBytes(&copy[0], &numbers[0], 3);
    Console.WriteLine(Text.FromInteger(copy[0] + copy[1] + copy[2]));

    var red = new Pixel(255, 0, 0);
    var other = new Pixel(0, 0, 0);
    CopyBytes(&other, &red, 1);
    Console.WriteLine(Text.FromInteger((int)other.R));

    Console.WriteLine(Text.FromInteger((long)SizeOf(red)));
    Console.WriteLine(Text.FromInteger((long)SizeOf(Level.High)));
    Console.WriteLine(Text.FromInteger((long)SizeOf((1, 2.0))));

    var registry = new Registry<String, Label>();
    registry.Add("a", new Label("first"));
    registry.Add("b", new Label("second"));
    Console.WriteLine(registry.KeyAt(1) + "=" + registry.At(1).Text);

    var counts = new Registry<int, long>();
    counts.Add(7, 49);
    Console.WriteLine(Text.FromInteger(counts.At(0)));

    Console.WriteLine(Describe(new Derived(), new Base()));
    return 0;
}
