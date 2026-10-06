// A `String` has no zero value, so the members that would leave an element
// without one are refused for a `String[]`, and `Buffer` takes plain data only.
module Bad;

int Main()
{
    String[] words = ["a", "b"];
    Array.Clear(words);                     // SL0328
    Array.Clear(words, 0u, 1u);             // SL0328
    Array.Resize(ref words, 4u);            // SL0328
    nuint size = Buffer.ByteLength(words);  // SL0328
    return 0;
}
