// A generic named over a struct that is declared further down the build.
//
// This file sorts first, so its members are declared first -- and naming
// `Result<Colour, Why>` here instantiates the variant while `Colour` is still a
// type with no fields. Laying that instantiation out at that moment reaches
// `Colour`, finds nothing in it, settles on one byte and caches the answer:
// `LayoutComputed` means nothing ever looks again.
//
// Nothing complains. The struct simply becomes one byte wide for the rest of
// the program, so a function returning one returns `i8`, every field past the
// first is dropped on the way out, and the values arrive truncated.
module Seam;

public enum Why { Cancelled, Failed }

public interface IChooser
{
    Result<Colour, Why> Choose(Colour start);
}

public Result<Colour, Why> Pick(Colour start) => Ok(start);
