// The debug format follows the target, and this is the half that says so on
// Windows.
//
// Built for Linux, so the description must be DWARF -- whatever machine the
// compiler is running on. Deciding by the host instead stamps a CodeView flag
// on an ELF, which is a description in a format nothing on that platform
// reads, and this case is what noticed.
module Format;

int Main()
{
    int counted = 3;
    return counted - 3;
}
