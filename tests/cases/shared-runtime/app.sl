// One runtime, shared by the program and the library it loads.
//
// The order of these lines is the test. Two runtimes meant two stdio buffers,
// and the library's output arrived whenever its buffer happened to flush --
// which is why the library in `stainless-library` reports through a counter the
// consumer can read rather than by printing.
module App;

import Standard.Console;
import Standard.Text;
import Talk;

int Main() {
    Console.WriteLine("app: one");
    Say("two");
    Console.WriteLine("app: three");
    Say("four");

    // Made there, held here, and dropped here: the destructor runs at the
    // closing brace, which only happens if both sides count the same object.
    {
        Note note = Make("held");
        Console.WriteLine("app: holding " + note.Text);
    }

    Console.WriteLine("app: dropped");

    // A String allocated by the library, measured by the program.
    String joined = Join("left", "right");
    Console.WriteLine("app: " + joined + " is "
        + Text.FromInteger(joined.ByteLength()) + " bytes");

    // And the same question asked from the other side of the boundary.
    Console.WriteLine("app: library agrees: "
        + Text.FromBool(Length(joined) == joined.ByteLength()));

    return 0;
}
