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

// A C function handing back an Objective-C object, owned by nobody knows whom.
extern "C" NSObject? NSClassFromString(byte* name);

void Uses(NSObject held)
{
    // A message held without being sent.
    Hasher later = held.Hash;

    // One made with 'new'.
    var made = new NSObject();
}

int Main() => 0;
