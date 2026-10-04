module Other;

import Standard.ObjC;

// A class of the same name declared by a module that does not import Home,
// so it is a class of its own, which a file importing both cannot add to.
[ObjCRoot]
public extern objc class Widget { }
