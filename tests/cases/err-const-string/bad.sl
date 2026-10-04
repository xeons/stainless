// SPDX-License-Identifier: 0BSD
//
// What a string constant may be: a C string or an immutable string object.
module BadConstString;

import Standard.ObjC;

[ObjCRoot]
public extern objc class NSObject { }

public extern objc class NSString : NSObject { }

public extern objc class NSMutableString : NSString { }

// A constant string cannot be mutated, so it is no NSMutableString.
public const NSMutableString Growing = "no";

// Text is not a list of numbers.
public const int* Numbers = "no";

// An int is not a string.
public const byte* Wrong = 5;

int Main() => 0;
