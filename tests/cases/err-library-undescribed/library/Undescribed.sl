// A public surface that names something the metadata leaves out.
//
// Both halves of the story are here. The library is told, where its author can
// do something about it (SLD0009); and a consumer that binds against it is told
// too, rather than finding a field of a type that is not there (SLD0006).
module Undescribed;

public variant Shape
{
    Round(double radius);
    Empty;
}

/// A described struct with an undescribed field.
public struct Holder // SLD0009
{
    public Shape Kind;
}

/// And a described function returning one, which used to arrive on the other
/// side as 'void' with nothing said at all.
public Shape Pick() => Shape.Empty; // SLD0009
