// What a Core Foundation type cannot be or do. Nothing here sends a message,
// so the case says the same on every host.
module BadCFTypes;

import Standard.ObjC;

[CFType]
public extern objc class CFTypeRef { }

[CFType("CFStringGetTypeID")]
public extern objc class CFStringRef : CFTypeRef { }

[CFType]
public extern objc class CFMutableStringRef : CFStringRef { }

[ObjCRoot]
public extern objc class NSObject { }

// A CF type answers no message.
[CFType("CFArrayGetTypeID")]
public extern objc class CFArrayRef : CFTypeRef
{
    [Selector("count")]
    public nuint Count { get; }
}

// An Objective-C class has no CF type to be built on.
public extern objc class NSThing : CFStringRef { }

// Nor is a protocol one.
[CFType]
public objc interface Copying { }

// Nor does it take an argument that is not a C function's name.
[CFType("not a name")]
public extern objc class CFBadRef : CFTypeRef { }

bool Ask(CFStringRef text) => text is CFMutableStringRef;

int Main() => 0;
