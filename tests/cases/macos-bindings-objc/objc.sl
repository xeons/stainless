// The generated Objective-C bindings used as a program uses them: Foundation's
// classes and blocks, AppKit's category on NSString from another module, a C
// variable holding an object, and Core Foundation's types, counted by ARC.
module BindingsObjC;

import Standard.Console;
import Standard.ObjC;
import MacOS.System;
import MacOS.CoreFoundation;
import MacOS.CoreGraphics;
import MacOS.Foundation;
import MacOS.AppKit;

String Text(NSString text) => Standard.Text.FromBytes(text.UTF8String, (nuint)text.Length);

NSString Make(byte* text) => NSString.StringWithUTF8String(text)!;

void Strings()
{
    var path = Make("/usr/local").StringByAppendingPathComponent(Make("bin"));
    Console.WriteLine($"path: {Text(path)}");

    var parts = Make("a,b,c").ComponentsSeparatedByString(Make(","));
    Console.WriteLine($"parts: {parts.Count}, the last {Text((NSString)parts.ObjectAtIndex(parts.Count - 1))}");

    var counted = new int[1];
    parts.EnumerateObjectsUsingBlock((AnyObject item, NSUInteger index, bool* stop) =>
    {
        counted[0]++;
        if (index == 1) *stop = true;
    });
    Console.WriteLine($"enumerated {counted[0]} before stopping");
}

void Categories()
{
    // sizeWithAttributes: is AppKit's, added to Foundation's NSString.
    var font = NSFont.SystemFontOfSize(13);
    var attributes = NSDictionary.DictionaryWithObjectForKey(font, NSFontAttributeName);
    var size = Make("Stainless").SizeWithAttributes(attributes);
    Console.WriteLine($"measured: {size.width > 0 && size.height > 0}");
}

void CoreFoundation()
{
    // Create hands the string over; the loop would climb if it were kept.
    for (int i = 0; i < 1000; i++)
        CFStringCreateWithCString(null, "made and dropped a thousand times", 0x08000100);

    var made = CFStringCreateWithCString(null, "a string Core Foundation made", 0x08000100)!;
    Console.WriteLine($"CF length {CFStringGetLength(made)}, owned {CFGetRetainCount(made)} time(s)");
    Console.WriteLine($"toll-free: {Text((NSString)made)}");

    CFTypeRef any = made;
    Console.WriteLine($"a string: {any is CFStringRef}, an array: {any is CFArrayRef}");

    // A CF value from a message, claimed like an object.
    var color = NSColor.ColorWithRedGreenBlueAlpha(1, 0.5, 0, 1).CGColor!;
    Console.WriteLine($"a color with {CGColorGetNumberOfComponents(color)} components");
}

int Main()
{
    WithAutoreleasePool(() => Strings());
    WithAutoreleasePool(() => Categories());
    WithAutoreleasePool(() => CoreFoundation());
    Console.WriteLine($"processors: {NSProcessInfo.ProcessInfo.ProcessorCount > 0}");
    return 0;
}
