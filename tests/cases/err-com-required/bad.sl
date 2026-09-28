// SPDX-License-Identifier: 0BSD
//
// A class factory makes a com class with no arguments and no initializer, so
// a `required` member would be left null. Only a constructor that sets them
// all, and says so with [SetsRequiredMembers], lets the class be activated.
module BadComRequired;

import Standard.Com;

[Guid("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")]
public com interface IGreeter { int Greet(); }

[Guid("bbbbbbbb-cccc-dddd-eeee-ffffffffffff")]
public com class Unset : IGreeter
{
    public required String Name;
    public int Greet() => (int)Name.ByteLength();
}

// Fine: the constructor answers for the required member.
[Guid("cccccccc-dddd-eeee-ffff-000000000000")]
public com class Set : IGreeter
{
    public required String Name;

    [SetsRequiredMembers]
    public Set() => Name = "set";

    public int Greet() => (int)Name.ByteLength();
}

public void Main()
{
}
