// A category in another module: what it adds is NSString's wherever NSString
// is seen, as an Objective-C category's methods are.
module Drawing;

import Standard.ObjC;
import Strings;

public objc interface Uppering
{
    [Selector("uppercaseString")]
    NSString Uppercase { get; }
}

public extern objc class NSString : Uppering
{
    [Selector("stringByAppendingString:")]
    public NSString Append(NSString other);

    // A helper, with a body, in a category.
    public NSString Shouted() => Append(NSString.FromUtf8("!")).Uppercase;
}
