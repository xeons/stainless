// SPDX-License-Identifier: 0BSD
//
// Only a record may derive from a record: a class would be compared and
// copied as its base, and what it added would be left out of both.
module ErrRecordDerived;

record Shape(int Id);

class Plain : Shape
{
    public Plain() : base(1) { }
}

int Main() => 0;
