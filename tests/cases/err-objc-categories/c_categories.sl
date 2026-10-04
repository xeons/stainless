module Categories;

import Standard.ObjC;
import Home;
import Other;

// A category names no superclass.
public extern objc class NSView : NSObject { }

// Home and Other both declare one.
public extern objc class Widget { }

int Main() => 0;
