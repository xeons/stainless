// SPDX-License-Identifier: 0BSD
module Bad;

// A [NoUnknown] vtable has no QueryInterface, so an IID would name something
// nothing could ask for.
[NoUnknown]
[Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
public com interface IBoth
{
    int Step();
}

[Guid("7e9fb0d3-919f-4307-ab2e-9b1860310c93")]
public com interface ICounted
{
    int Step();
}

// And the two kinds cannot share a chain: extending the other would put
// IUnknown three slots into the middle of one table.
[NoUnknown]
public com interface IMixed : ICounted
{
    int Extra();
}

// [NoUnknown] says something about a COM vtable, and a struct has none.
[NoUnknown]
public struct Plain
{
    public int Value;
}

int Main() => 0;
