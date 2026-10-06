// A `String` has no zero value, so the members that would leave an element
// without one are refused for a `String[]`, and `Buffer` takes plain data only.
module Bad;

int Main()
{
    String[] words = ["a", "b"];
    Array.Clear(words);                     // SLG0006
    Array.Clear(words, 0u, 1u);             // SLG0006
    Array.Resize(ref words, 4u);            // SLG0006
    nuint size = Buffer.ByteLength(words);  // SLG0006
    return 0;
}
