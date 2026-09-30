// A variant with no tag is described to DWARF as a variant part: the word
// whose null is the empty case is the discriminator, the empty case is that
// word being zero, and the case holding a value is the default.
module DebugVariantNiche;

int Count(Optional<String> held)
{
    Optional<String> copy = held;
    return copy is Some ? 1 : 0;
}

int Main() => Count("held") - 1;
