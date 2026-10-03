// A record cannot be an Objective-C class: 'with' copies one field by field.
module BadObjCRecord;

import Standard.ObjC;

[ObjCRoot]
public extern objc class NSObject
{
}

public objc record Point(long X, long Y) : NSObject;

int Main() => 0;
