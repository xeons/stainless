// SPDX-License-Identifier: 0BSD
module ReflectionOwnership;

import Standard.Console;
import Standard.Reflection;

public class Tag
{
    public String Name;

    public Tag(String name)
    {
        Name = name;
    }

    ~Tag() { Console.WriteLine($"  dropped {Name}"); }
}

[Reflect]
public class Holder
{
    public nint Wide;
    public int After;
    public nuint WideUnsigned;
    public int Last;
    public char16 Unit;
    public char32 Scalar;
    public bool Flag;
    public int Number;
    public String Label;

    public Tag? Item { get; set; }
    public String Caption { get; set; }
    public nint Span { get; set; }
    public int Guard { get; set; }

    public Holder()
    {
        Label = "";
        Caption = "";
    }
}

void CheckAggregate()
{
    var holder = new Holder();
    var raw = (byte*)holder;
    var item = typeof(Holder).FindProperty("Item");

    SetAggregate(raw, item, (byte*)new Tag("first"));
    byte* back = GetAggregate(raw, item);
    Console.WriteLine($"  read back {back != null}");

    SetAggregate(raw, item, (byte*)new Tag("second"));
    Console.WriteLine("  replaced");
    holder.Item = null;
    Console.WriteLine("  cleared");
}

void CheckFields()
{
    var holder = new Holder();
    var raw = (byte*)holder;
    var type = typeof(Holder);

    holder.After = 7;
    holder.Last = 9;
    WriteInteger(raw, type.FindField("Wide"), -5);
    WriteInteger(raw, type.FindField("WideUnsigned"), 123456);
    Console.WriteLine($"  nint {holder.Wide} {ReadInteger(raw, type.FindField("Wide"))}");
    Console.WriteLine($"  nuint {holder.WideUnsigned} {ReadInteger(raw, type.FindField("WideUnsigned"))}");
    Console.WriteLine($"  neighbours {holder.After} {holder.Last}");

    holder.Unit = (char16)0x263A;
    holder.Scalar = (char32)0x1F600;
    Console.WriteLine($"  char16 {ReadInteger(raw, type.FindField("Unit"))}");
    Console.WriteLine($"  char32 {ReadInteger(raw, type.FindField("Scalar"))}");

    holder.Flag = true;
    holder.Number = 2;
    Console.WriteLine($"  bool {ReadBool(raw, type.FindField("Flag"))}");
    Console.WriteLine($"  bool of int {ReadBool(raw, type.FindField("Number"))}");

    holder.Label = "hello";
    Console.WriteLine($"  text {ReadText(raw, type.FindField("Label"))}");
    holder.Label = "a\0b";
    Console.WriteLine($"  text length {ReadText(raw, type.FindField("Label")).ByteLength()}");
}

void CheckProperties()
{
    var holder = new Holder();
    var raw = (byte*)holder;
    var caption = typeof(Holder).FindProperty("Caption");

    SetText(raw, caption, "world");
    Console.WriteLine($"  get text {GetText(raw, caption)}");
    SetText(raw, caption, "x\0y");
    Console.WriteLine($"  get text length {GetText(raw, caption).ByteLength()}");
    Console.WriteLine($"  set text length {holder.Caption.ByteLength()}");

    var span = typeof(Holder).FindProperty("Span");
    holder.Guard = 11;
    SetInteger(raw, span, -3);
    Console.WriteLine($"  nint property {holder.Span} {GetInteger(raw, span)} {holder.Guard}");
}

public int Main()
{
    Console.WriteLine("aggregate");
    CheckAggregate();
    Console.WriteLine("fields");
    CheckFields();
    Console.WriteLine("properties");
    CheckProperties();
    Console.WriteLine("done");
    return 0;
}
