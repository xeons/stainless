// A cast to a Core Foundation type the object is not stops the program.
module CFCast;

import Standard.Console;
import Standard.ObjC;

#pragma comment(framework, "CoreFoundation")

[CFType]
public extern objc class CFTypeRef { }

[CFType("CFStringGetTypeID")]
public extern objc class CFStringRef : CFTypeRef { }

[CFType("CFNumberGetTypeID")]
public extern objc class CFNumberRef : CFTypeRef { }

[ReturnsRetained]
extern "C" CFStringRef CFStringCreateWithCString(void* allocator, byte* text, uint encoding);

int Main()
{
    CFTypeRef any = CFStringCreateWithCString(null, "a string too long to be a tagged pointer", 0x08000100);
    Console.WriteLine("asking");
    var number = (CFNumberRef)any;
    Console.WriteLine("not reached");
    return 0;
}
