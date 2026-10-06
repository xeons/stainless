// What a class defined for Objective-C may be. Each is refused before
// anything is emitted, so the case needs no Mac.
module BadObjCDefined;

import Standard.ObjC;

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("alloc")]
    public static Self Alloc();
    [Selector("init")]
    public Self Init();
    [Selector("hash")]
    public nuint Hash { get; }
}

public objc interface Named
{
    [Selector("name")]
    long Name();
}

// No superclass.
public objc class Lonely
{
}

// 'virtual', an override of nothing, and a selector the superclass answers.
public objc class Overrides : NSObject
{
    public virtual long Spare() => 1;
    public override long Missing() => 2;
    [Selector("hash")]
    public nuint MyHash => 3;
    [Selector("twice")]
    public long First() => 1;
    [Selector("twice")]
    public long Second() => 2;
}

// An override answers the selector it overrides, not one of its own.
public objc class Renamed : NSObject
{
    [Selector("myHash")]
    public override nuint Hash => 4;
}

// A root that answers no init.
[ObjCRoot]
public extern objc class Uninitialized
{
    [Selector("alloc")]
    public static Self Alloc();
}

public objc class OnUninitialized : Uninitialized
{
}

// A required protocol member nobody answers.
public objc class Unanswered : NSObject, Named
{
}

// A static class.
public static objc class Static : NSObject
{
}

// A generic method answering a selector.
public objc class Generic : NSObject
{
    [Selector("pick:")]
    public long Pick<T>(long value) => value;
}

// A constructor whose selector is not an init.
public objc class NotInit : NSObject
{
    [Selector("make:")]
    public NotInit(long value) { }
}

// A field with no zero value and no initializer.
public objc class Unset : NSObject
{
    String _name;
}

int Main()
{
    // 'typeof' on an Objective-C class.
    var described = typeof(Unset);

    // Nothing it is built on declares 'init'.
    var made = new OnUninitialized();
    return 0;
}
