module Strings;

import Standard.ObjC;

#pragma comment(framework, "Foundation")

[ObjCRoot]
public extern objc class NSObject { }

public extern objc class NSString : NSObject
{
    [Selector("stringWithUTF8String:")] public static Self FromUtf8(byte* text);
    [Selector("UTF8String")] public byte* Utf8 { get; }
}
