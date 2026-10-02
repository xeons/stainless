// What a member of an Objective-C type has to say about its message.
module BadObjCSelectors;

import Standard.ObjC;

[ObjCRoot]
public extern objc class NSObject
{
    // No selector, and no body to be a helper with.
    public void Forgotten();

    // A selector and a body: the class already has the method.
    [Selector("description")]
    public NSObject Description() => this;

    // Not a selector at all.
    [Selector("not a selector")]
    public void Spaced();

    // One colon, and two arguments to carry.
    [Selector("setX:")]
    public void SetBoth(int x, int y);

    // '[Optional]' on a class's member.
    [Optional, Selector("hash")]
    public nuint Hash();

    // A String, which a message cannot carry.
    [Selector("setName:")]
    public void SetName(String name);
}

int Main() => 0;
