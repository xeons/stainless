// What a program may not do with an Objective-C object. Nothing here sends a
// message, so the case says the same on every host.
module BadObjCUses;

import Standard.ObjC;

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("hash")] public nuint Hash();
}

public closure nuint Hasher();

// A C++ function handing back an Objective-C object: C++ has no rule for who owns it.
extern "C++" NSObject? MakeObject();

// An object C holds, which is read and never written.
extern "C" NSObject NSApp;

// Ownership said of a call that hands back no object.
[ReturnsRetained] extern "C" int CountObjects();

void Uses(NSObject held)
{
    // A message held without being sent.
    Hasher later = held.Hash;

    // One made with 'new'.
    var made = new NSObject();

    NSApp = held;
}

int Main() => 0;
