// SPDX-License-Identifier: 0BSD
//
// `StringBuilder.AppendInteger`, against `Text.FromInteger`.
//
// The builder formats into its own buffer a digit at a time rather than
// allocating a `String` per number, so the two have separate code and must
// agree. What that code can get wrong is the edges: zero, the sign, and the
// smallest long, whose magnitude is not itself a long and which a naive
// negation turns back into itself.
//
// The growth either side of the first allocation is here too, because a
// builder that reserves wrongly is a builder that overwrites what it built.
module BuilderNumbers;

import Standard.Console;
import Standard.Text;
import Standard.Limits;

static int s_wrong = 0;

/// Both ways of turning one number into text, which must not differ.
void Same(long value)
{
    var built = new StringBuilder();
    built.AppendInteger(value);

    String mine = built.ToText();
    String theirs = FromInteger(value);

    if (mine == theirs)
        return;

    s_wrong++;
    Console.WriteLine("differ: builder " + mine + ", FromInteger " + theirs);
}

int Main()
{
    Same(0);
    Same(1);
    Same(-1);
    Same(9);
    Same(10);
    Same(-10);
    Same(99);
    Same(100);
    Same(-100);
    Same(12345);
    Same(-12345);
    Same(1000000000);
    Same(MaxInt);
    Same(MinInt);
    Same(MaxLong);

    // The one a negation gets wrong.
    Same(MinLong);
    Same(MinLong + 1);

    Console.WriteLine(s_wrong == 0 ? "numbers agree" : "numbers differ");

    // ------------------------------------------------------------- growing

    // The buffer starts at nothing, takes 32 bytes at the first append, and
    // doubles. Appending one byte at a time across both boundaries catches a
    // reserve that is off by one or that forgets what was already there.
    var grown = new StringBuilder();
    for (nuint i = 0u; i < 100u; i++)
        grown.AppendByte((byte)(0x30u + (uint)(i % 10u)));

    Console.WriteLine("grown " + Text.FromInteger(grown.ByteLength()));
    Console.WriteLine("head " + grown.ToText().Substring(0u, 12u));
    Console.WriteLine("tail " + grown.ToText().Substring(88u, 12u));

    // Cleared and refilled: the room is kept, so this reuses the allocation.
    grown.Clear();
    Console.WriteLine("cleared " + (grown.IsEmpty ? "empty" : "not"));
    grown.Append("after");
    Console.WriteLine("reused " + grown.ToText());

    // ------------------------------------------------------------- editing

    // Inserting at the length is appending, and removing past the end stops at
    // the end rather than failing.
    var edited = new StringBuilder();
    edited.Append("hello");
    edited.Insert(0u, ">");
    edited.Insert(edited.ByteLength(), "<");
    Console.WriteLine("edited " + edited.ToText());

    edited.Remove(2u, 1000u);
    Console.WriteLine("trimmed " + edited.ToText());

    // A builder with nothing in it answers with nothing rather than failing.
    var empty = new StringBuilder();
    Console.WriteLine("empty [" + empty.ToText() + "]");
    Console.WriteLine("empty length " + Text.FromInteger(empty.ByteLength()));

    return s_wrong == 0 ? 0 : 1;
}
