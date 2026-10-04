// NSString and CFStringRef constants: the object clang makes of @"..." and
// CFSTR("..."), compiled in. They equal strings made at run time, survive
// being counted as any object is, and hold text that is not ASCII.
module ObjCConstStrings;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject { }

public extern objc class NSString : NSObject
{
    [Selector("stringWithUTF8String:")] public static NSString FromUtf8(byte* text);
    [Selector("length")] public nuint Length { get; }
    [Selector("isEqualToString:")] public bool IsEqualToString(NSString other);
    [Selector("characterAtIndex:")] public char16 CharacterAt(nuint index);
}

[CFType]
public extern objc class CFTypeRef { }

[CFType("CFStringGetTypeID")]
public extern objc class CFStringRef : CFTypeRef { }

extern "C"
{
    long CFStringGetLength(CFStringRef text);
    bool CFEqual(CFTypeRef first, CFTypeRef second);
}

public const NSString Greeting = "hello, world";
public const NSString Coffee = "caf\u00e9 \u2615";
public const CFStringRef Key = "kSecAttrAccessible";

int Main()
{
    Console.WriteLine($"Greeting: {Greeting.Length} characters, equal to one made now: {Greeting.IsEqualToString(NSString.FromUtf8("hello, world"))}");
    Console.WriteLine($"Coffee: {Coffee.Length} units, the e is U+{(int)Coffee.CharacterAt(3):X4}, the cup U+{(int)Coffee.CharacterAt(5):X4}");
    Console.WriteLine($"Key: {CFStringGetLength(Key)} characters, a string: {Key is CFStringRef}");

    // A CFSTR and an @"..." of one text are toll-free the same kind of thing.
    Console.WriteLine($"toll-free: {CFEqual(Key, (CFTypeRef)(AnyObject)NSString.FromUtf8("kSecAttrAccessible"))}");

    // Read, held and dropped many times: a constant is never freed.
    nuint total = 0;
    for (int i = 0; i < 10000; i++)
    {
        NSString held = Greeting;
        total = total + held.Length;
    }
    Console.WriteLine($"read ten thousand times: {total}");
    return 0;
}
