// A message sent by a program built for a system with no Objective-C.
module NotDarwin;

import Standard.ObjC;

[ObjCRoot]
public extern objc class NSObject
{
    [Selector("hash")] public nuint Hash();
}

nuint Hashed(NSObject held) => held.Hash();

int Main() => 0;
