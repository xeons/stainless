// What COM refuses, and why.
//
// Most of these are the same rule stated once: a COM reference is one pointer
// to one vtable, and everything that would need a second one is out.
module BadCom;

import Standard.Com;

// 'com' goes before 'interface' or 'class'; a struct has no vtable pointer.
public com struct NotAType { public int X; }

// A com interface with no [Guid] has no identity, so nothing could ever ask an
// object for it.
public com interface INoIdentity {
    int Value();
}

[Guid("11111111-2222-3333-4444-555555555555")]
public com interface IFirst { int One(); }

[Guid("22222222-3333-4444-5555-666666666666")]
public com interface ISecond { int Two(); }

// One vtable, one chain: two bases would need two vtable pointers and a COM
// reference has room for one.
[Guid("33333333-4444-5555-6666-777777777777")]
public com interface IBoth : IFirst, ISecond { int Three(); }

// A COM vtable is one flat array with IUnknown at the front; a Stainless
// interface is reached through the object header instead.
public interface IPlain { int Plain(); }

[Guid("44444444-5555-6666-7777-888888888888")]
public com interface IMixed : IPlain { int Mixed(); }

// A '[Guid]' that is not one.
[Guid("not-a-guid")]
public com interface IMalformed { int Value(); }

// '[Guid]' on something that has no IID.
[Guid("55555555-6666-7777-8888-999999999999")]
public class NotCom { public int Value() { return 0; } }

// An ordinary class cannot present a com interface: it has no room for a
// vtable pointer, which is what 'com class' reserves.
public class Ordinary : IFirst {
    public int One() { return 1; }
}

// A com class has to present something, or nothing outside could hold it.
public com class Presents { public int X() { return 0; } }

// The methods are still the contract, so a missing one is a missing one.
public com class Incomplete : IFirst { }

// An interface that adds nothing to IUnknown is IUnknown under another name.
[Guid("66666666-7777-8888-9999-aaaaaaaaaaaa")]
public com interface IEmpty { }

// An interface has one identity.
[Guid("77777777-8888-9999-aaaa-bbbbbbbbbbbb")]
[Guid("88888888-9999-aaaa-bbbb-cccccccccccc")]
public com interface ITwice { int Value(); }

// A com class's tear-offs sit after its fields, and a derived class adds
// fields after those, so the two cannot be combined yet.
public class Base { public int X; }

[Guid("99999999-aaaa-bbbb-cccc-dddddddddddd")]
public com interface IThird { int Three(); }

public com class Derived : Base, IThird {
    public int Three() { return 3; }
}

public void Main() {
    // 'iidof' names a com interface's [Guid], and IPlain has none.
    Guid* g = iidof(IPlain);
}
