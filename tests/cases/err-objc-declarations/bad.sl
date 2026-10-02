// What an Objective-C declaration may be, and what it may derive from.
module BadObjCDeclarations;

import Standard.ObjC;

[ObjCRoot]
public extern objc class NSObject
{
}

// 'objc' on a struct.
public objc struct NotObjC
{
    public int Value;
}

// 'extern' on a protocol.
public extern objc interface Described
{
}

// '[ObjCName]' on a Stainless class.
[ObjCName("Plain")]
public class Plain
{
}

// A field in a class that only describes one that exists.
public extern objc class NSView : NSObject
{
    int _count;
}

// An Objective-C class deriving from a Stainless one.
public extern objc class Mixed : Plain
{
}

// A chain that stops short of a root.
public extern objc class Rootless
{
}

int Main() => 0;
