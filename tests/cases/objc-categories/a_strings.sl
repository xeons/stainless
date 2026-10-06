// A part of NSString ahead of the part that names its superclass: the order
// of a module's files says nothing about which part is the class.
module Strings;

import Standard.ObjC;

public objc interface Lowering
{
    [Selector("lowercaseString")]
    NSString Lowercase { get; }
}

public extern objc class NSString : Lowering
{
    [Selector("length")]
    public nuint Length { get; }
}
