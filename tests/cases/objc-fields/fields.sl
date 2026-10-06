// Fields of classes defined in Stainless: their initializers run however the
// object is made, constructors are inits Objective-C can send, every field
// is freed once the object is, and the ivar holding them slides past a
// superclass whose size only the runtime knows.
module ObjCFields;

import Standard.Collections;
import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("alloc")]
    public static Self Alloc();
    [Selector("init")]
    public Self Init();
}

public extern objc class NSString : NSObject
{
    [Selector("stringWithUTF8String:")]
    public static Self FromUtf8(byte* text);
    [Selector("length")]
    public nuint Length { get; }
}

// Written in probe.m, with ivars of its own.
public extern objc class SLBase : NSObject
{
    [Selector("initWithBase:")]
    public Self InitWithBase(long value);
    [Selector("baseValue")]
    public long BaseValue { get; }
}

public struct Tag
{
    public String Text;
    public long Weight;
}

Tag MakeTag(String text)
{
    Tag tag;
    tag.Text = text;
    tag.Weight = (long)text.ByteLength();
    return tag;
}

public objc class Counter : SLBase
{
    public static int Made = 0;
    public static int Destroyed = 0;

    long _count = 10;
    String _label = "counter";
    List<long> _seen = new List<long>();
    NSString? _note;
    Tag _tag = MakeTag("tagged");

    // Answers init: Objective-C's [[Counter alloc] init] runs it.
    public Counter() : base(7)
    {
        Made++;
    }

    [Selector("initWithCount:")]
    public Counter(long count) : base(count * 100)
    {
        _count = count;
        _note = NSString.FromUtf8("noted");
        Made++;
    }

    [Selector("count")]
    public long Count => _count;
    [Selector("seen")]
    public long Seen => (long)_seen.Count;
    [Selector("labelLength")]
    public long LabelLength => (long)_label.ByteLength() + _tag.Weight;
    [Selector("noteLength")]
    public long NoteLength => _note is NSString note ? (long)note.Length : -1;

    [Selector("bump")]
    public void Bump()
    {
        _count++;
        _seen.Add(_count);
        _label = $"{_label}+";
    }

    ~Counter()
    {
        Destroyed++;
    }
}

// Its fields go in an ivar of their own, after Counter's.
public objc class Wider : Counter
{
    long _extra = 5;
    String _name = "wider";

    [Selector("initWithExtra:")]
    public Wider(long extra) : base(extra)
    {
        _extra = extra * 2;
    }

    [Selector("extra")]
    public long Extra => _extra + (long)_name.ByteLength();
}

extern "C"
{
    long SLCountAfterInit(byte* name);
    long SLBaseAfterInit(byte* name);
    long SLCountWithCount(long count);
    long SLBaseWithCount(long count);
    long SLExtraWithExtra(long extra);
    long SLIvarOffset(byte* name);
    long SLInstanceSize(byte* name);
    long SLBaseSize();
    long SLNoteLengthAfterInit();
}

void FromStainless()
{
    var made = new Counter();
    Console.WriteLine($"made: count {made.Count} base {made.BaseValue} note {made.NoteLength}");

    var counted = new Counter(3);
    counted.Bump();
    counted.Bump();
    Console.WriteLine($"counted: count {counted.Count} base {counted.BaseValue} seen {counted.Seen} label {counted.LabelLength} note {counted.NoteLength}");

    var wider = new Wider(4);
    wider.Bump();
    Console.WriteLine($"wider: count {wider.Count} base {wider.BaseValue} extra {wider.Extra} seen {wider.Seen}");
}

void FromObjectiveC()
{
    Console.WriteLine($"init: count {SLCountAfterInit("ObjCFields.Counter")} base {SLBaseAfterInit("ObjCFields.Counter")} note {SLNoteLengthAfterInit()}");
    Console.WriteLine($"initWithCount: count {SLCountWithCount(6)} base {SLBaseWithCount(6)}");
    Console.WriteLine($"initWithExtra: extra {SLExtraWithExtra(9)}");
}

void Layout()
{
    long counter = SLIvarOffset("ObjCFields.Counter");
    long wider = SLIvarOffset("ObjCFields.Wider");
    Console.WriteLine($"Counter's ivar is past SLBase: {counter >= SLBaseSize()}");
    Console.WriteLine($"Wider's ivar is past Counter: {wider >= SLInstanceSize("ObjCFields.Counter")}");
    Console.WriteLine($"Wider ends past its ivar: {SLInstanceSize("ObjCFields.Wider") > wider}");
}

int Main()
{
    WithAutoreleasePool(() => FromStainless());
    WithAutoreleasePool(() => FromObjectiveC());
    Layout();
    Console.WriteLine($"made {Counter.Made}, destroyed {Counter.Destroyed}");
    return 0;
}
