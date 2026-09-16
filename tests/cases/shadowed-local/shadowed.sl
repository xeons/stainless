// A name may not be reused inside the scope that already has one, which is
// C#'s rule rather than C's: where two readings of a name are possible, the
// likelier cause is a mistake. Documented in §9 of the specification.
module Shadowed;

int Main()
{
    int n = 1;
    {
        int n = 2;      // the enclosing block already has one
        n++;
    }
    return n;
}
