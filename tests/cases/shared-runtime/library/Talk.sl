// The library half. It prints, which before the runtime was shared it could not
// usefully do: a copy of the runtime linked into each binary meant a stdio
// buffer each, and what a library wrote did not interleave with its consumer's
// in the order the two of them wrote it.
module Talk;

import Standard.Console;
import Standard.Text;

public void Say(String what) {
    Console.WriteLine("  library: " + what);
}

/// An object made here and dropped there. With one runtime the count is one
/// count, so the destructor runs when the consumer lets go and not before.
public class Note {
    public String Text;

    Note(String text) { Text = text; }

    ~Note() { Console.WriteLine("  library: dropping " + Text); }
}

public Note Make(String text) { return new Note(text); }

/// A string made on this side and read on the other. Both sides ask the same
/// allocator for it, and the type it carries is the one runtime's.
public String Join(String left, String right) { return left + "/" + right; }

public nuint Length(String text) { return text.ByteLength(); }
