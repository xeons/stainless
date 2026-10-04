// Core Foundation types counted by ARC: what a Create function hands over is
// owned once, a cast down asks the object's CFTypeID, and a CF object is an
// Objective-C object wherever one is wanted.
module CFTypes;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[CFType]
public extern objc class CFTypeRef { }

[CFType("CFStringGetTypeID")]
public extern objc class CFStringRef : CFTypeRef { }

[CFType]
public extern objc class CFMutableStringRef : CFStringRef { }

[CFType("CFNumberGetTypeID")]
public extern objc class CFNumberRef : CFTypeRef { }

[ObjCRoot]
public extern objc class NSObject { }

public extern objc class NSString : NSObject
{
    [Selector("length")] public nuint Length { get; }
}

[ReturnsRetained] extern "C" CFStringRef CFStringCreateWithCString(void* allocator, byte* text, uint encoding);
[ReturnsRetained] extern "C" CFMutableStringRef CFStringCreateMutable(void* allocator, long most);
extern "C" void CFStringAppendCString(CFMutableStringRef text, byte* more, uint encoding);
extern "C" long CFStringGetLength(CFStringRef text);
[ReturnsRetained] extern "C" CFNumberRef CFNumberCreate(void* allocator, long type, void* value);
extern "C" long CFGetRetainCount(CFTypeRef cf);

const uint Utf8 = 0x08000100;

int Main()
{
    var text = CFStringCreateWithCString(null, "a string made by CF", Utf8);
    Console.WriteLine($"length {CFStringGetLength(text)}, owned {CFGetRetainCount(text)} time(s)");

    var growing = CFStringCreateMutable(null, 0);
    CFStringAppendCString(growing, "grown", Utf8);
    CFStringRef seen = growing;
    Console.WriteLine($"mutable, seen as immutable: {CFStringGetLength(seen)}");

    long value = 42;
    var number = CFNumberCreate(null, 4, &value);

    CFTypeRef any = text;
    Console.WriteLine($"a string is a string: {any is CFStringRef}, a number: {any is CFNumberRef}");
    CFTypeRef other = number;
    Console.WriteLine($"a number is a string: {other is CFStringRef}");
    var back = (CFStringRef)any;
    Console.WriteLine($"cast back: {CFStringGetLength(back)}");

    // Toll-free bridged: the same object is an NSString.
    var bridged = (NSString)text;
    Console.WriteLine($"as an NSString: {bridged.Length}");
    AnyObject anything = text;
    Console.WriteLine($"an object is a CFTypeRef: {CFGetRetainCount((CFTypeRef)anything) > 0}");

    CFStringRef? none = null;
    CFTypeRef? nothing = none;
    Console.WriteLine($"nil is no string: {nothing is CFStringRef}");

    // Made and dropped many times: each is freed, or the count of the last
    // would climb with the ones before.
    for (int i = 0; i < 10000; i++)
    {
        var made = CFStringCreateWithCString(null, "again, long enough to be allocated", Utf8);
        if (i == 9999) Console.WriteLine($"the last owned {CFGetRetainCount(made)} time(s)");
    }
    return 0;
}
