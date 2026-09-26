// SPDX-License-Identifier: 0BSD
module Bad;

// Only a run of quotes as long as the opening one closes a raw string, and
// the number of '$' is how many braces open a hole.
int Main()
{
    int n = 1;
    String quotes = """ends with four"""";
    String braces = $"""{{n}}""";
    String dollars = $$"{n}";
    return (int)(quotes.ByteLength() + braces.ByteLength() + dollars.ByteLength());
}
