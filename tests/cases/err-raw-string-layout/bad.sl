// SPDX-License-Identifier: 0BSD
module Bad;

// A raw string across lines is its lines between the quotes, and the closing
// quotes' indentation is taken off each: so the quotes stand on lines of their
// own, and every line starts with that indentation.
int Main()
{
    String opening = """text
        """;
    String closing = """
        text""";
    String outdented = """
        indented
      not
        """;
    return (int)(opening.ByteLength() + closing.ByteLength() + outdented.ByteLength());
}
