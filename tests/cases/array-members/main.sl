// `Array` and `Buffer`, .NET's static members over arrays. A `String` array
// takes every path that needs no zero value: `Resize` with a fill, `Fill`,
// `Copy`, the searches and the sorts.
module ArrayMembers;

import Standard.Console;

public struct Pair
{
    public short Low;
    public short High;
}

String FormatNumbers(int[] numbers) => ",".Join(Array.ConvertAll(numbers, (n) => $"{n}"));

String FormatWords(String[] words) => ",".Join(words);

String FormatFound(Optional<nuint> found)
{
    if (found is Some at)
        return $"{at.Value}";
    return "none";
}

String FormatWord(Optional<String> found)
{
    if (found is Some word)
        return word.Value;
    return "none";
}

void ShowMaking()
{
    int[] none = Array.Empty<int>();
    String[] noWords = Array.Empty<String>();
    Console.WriteLine($"empty {none.Length} {noWords.Length}");

    String[] words = ["b", "a"];
    ReadOnlySpan<String> view = Array.AsReadOnly(words);
    Console.WriteLine($"view {view.Length} {view[1]}");

    String[] lengths = Array.ConvertAll(["one", "three"], (w) => $"{w.ByteLength()}");
    Console.WriteLine($"convert {FormatWords(lengths)}");
}

void ShowResizing()
{
    int[] numbers = [1, 2, 3];
    Array.Resize(ref numbers, 5u);
    Console.WriteLine($"grow {FormatNumbers(numbers)}");
    Array.Resize(ref numbers, 2u);
    Console.WriteLine($"shrink {FormatNumbers(numbers)}");

    String[] words = ["x"];
    String[] before = words;
    Array.Resize(ref words, 3u, "pad");
    Console.WriteLine($"fill {FormatWords(words)} old {FormatWords(before)}");
    Array.Resize(ref words, 1u, "unused");
    Console.WriteLine($"cut {FormatWords(words)}");
}

void ShowCopying()
{
    int[] numbers = [1, 2, 3, 4, 5];
    var target = new int[5];
    Array.Copy(numbers, target, 3u);
    Console.WriteLine($"copy {FormatNumbers(target)}");

    Array.Copy(numbers, 0u, numbers, 1u, 4u);
    Console.WriteLine($"overlap {FormatNumbers(numbers)}");

    String[] words = ["a", "b", "c", "d"];
    String[] into = ["-", "-", "-"];
    Array.Copy(words, 1u, into, 0u, 3u);
    Console.WriteLine($"words {FormatWords(into)}");

    Array.Clear(numbers, 1u, 2u);
    Console.WriteLine($"clear part {FormatNumbers(numbers)}");
    Array.Clear(numbers);
    Console.WriteLine($"clear {FormatNumbers(numbers)}");

    Array.Fill(numbers, 7);
    Array.Fill(numbers, 9, 3u, 2u);
    Console.WriteLine($"fill {FormatNumbers(numbers)}");
    Array.Fill(into, "z", 1u, 1u);
    Console.WriteLine($"fill words {FormatWords(into)}");

    Array.Reverse(words);
    Console.WriteLine($"reverse {FormatWords(words)}");
    Array.Reverse(words, 1u, 2u);
    Console.WriteLine($"reverse part {FormatWords(words)}");
}

void ShowOrdering()
{
    String[] words = ["pear", "fig", "apple", "kiwi"];
    Array.Sort(words);
    Console.WriteLine($"sort {FormatWords(words)}");

    Array.Sort(words, (a, b) => (int)a.ByteLength() - (int)b.ByteLength());
    Console.WriteLine($"by length {FormatWords(words)}");

    int[] numbers = [9, 5, 3, 1, 0];
    Array.Sort(numbers, 1u, 3u);
    Console.WriteLine($"sort part {FormatNumbers(numbers)}");
    Array.Sort(numbers, 0u, 4u, (a, b) => b - a);
    Console.WriteLine($"descending part {FormatNumbers(numbers)}");

    int[] keys = [3, 1, 2];
    String[] items = ["c", "a", "b"];
    Array.Sort(keys, items);
    Console.WriteLine($"keys {FormatNumbers(keys)} {FormatWords(items)}");
    Array.Sort(keys, items, (a, b) => b - a);
    Console.WriteLine($"keys down {FormatNumbers(keys)} {FormatWords(items)}");

    int[] ordered = [1, 3, 5, 7, 9];
    Console.WriteLine($"binary {FormatFound(Array.BinarySearch(ordered, 7))} " +
        $"{FormatFound(Array.BinarySearch(ordered, 4))} " +
        $"{FormatFound(Array.BinarySearch(ordered, 1u, 2u, 5))} " +
        $"{FormatFound(Array.BinarySearch(ordered, 1u, 2u, 7))}");
}

void ShowSearching()
{
    String[] words = ["a", "b", "a", "c", "a"];
    Console.WriteLine($"index {FormatFound(Array.IndexOf(words, "a"))} " +
        $"{FormatFound(Array.IndexOf(words, "a", 1u))} " +
        $"{FormatFound(Array.IndexOf(words, "a", 3u, 1u))} " +
        $"{FormatFound(Array.IndexOf(words, "z"))}");
    Console.WriteLine($"last {FormatFound(Array.LastIndexOf(words, "a"))} " +
        $"{FormatFound(Array.LastIndexOf(words, "a", 3u))} " +
        $"{FormatFound(Array.LastIndexOf(words, "c", 4u, 2u))} " +
        $"{FormatFound(Array.LastIndexOf(words, "c", 4u, 1u))}");

    String[] none = Array.Empty<String>();
    Console.WriteLine($"last empty {FormatFound(Array.LastIndexOf(none, "a", 0u))} " +
        $"{FormatFound(Array.FindLastIndex(none, (w) => true))}");

    int[] numbers = [4, 7, 10, 13, 16];
    Console.WriteLine($"exists {Array.Exists(numbers, (n) => n > 15)} " +
        $"{Array.Exists(numbers, (n) => n > 99)}");
    Console.WriteLine($"all {Array.TrueForAll(numbers, (n) => n > 0)} " +
        $"{Array.TrueForAll(numbers, (n) => n % 2 == 0)}");

    String[] fruit = ["fig", "pear", "plum", "kiwi"];
    Console.WriteLine($"find {FormatWord(Array.Find(fruit, (w) => w.StartsWith("p")))} " +
        $"{FormatWord(Array.FindLast(fruit, (w) => w.StartsWith("p")))} " +
        $"{FormatWord(Array.Find(fruit, (w) => w.StartsWith("q")))}");
    Console.WriteLine($"find all {FormatWords(Array.FindAll(fruit, (w) => w.ByteLength() == 4u))}");

    Console.WriteLine($"find index {FormatFound(Array.FindIndex(numbers, (n) => n > 5))} " +
        $"{FormatFound(Array.FindIndex(numbers, 2u, (n) => n % 2 == 1))} " +
        $"{FormatFound(Array.FindIndex(numbers, 1u, 2u, (n) => n > 12))}");
    Console.WriteLine($"find last index {FormatFound(Array.FindLastIndex(numbers, (n) => n < 12))} " +
        $"{FormatFound(Array.FindLastIndex(numbers, 1u, (n) => n % 2 == 0))} " +
        $"{FormatFound(Array.FindLastIndex(numbers, 4u, 2u, (n) => n < 12))}");

    String[] seen = ["", "", "", ""];
    nuint at = 0u;
    Array.ForEach(fruit, (w) =>
    {
        seen[at] = w.ToUpperAscii();
        at++;
    });
    Console.WriteLine($"for each {FormatWords(seen)}");
}

void ShowBuffer()
{
    int[] numbers = [0x04030201, 0x08070605];
    var bytes = new byte[Buffer.ByteLength(numbers)];
    Buffer.BlockCopy(numbers, 0u, bytes, 0u, Buffer.ByteLength(numbers));
    Console.WriteLine($"bytes {bytes.Length} {bytes[0]} {bytes[4]} {bytes[7]}");

    Buffer.BlockCopy(bytes, 1u, bytes, 0u, 3u);
    Console.WriteLine($"overlap {bytes[0]} {bytes[1]} {bytes[2]} {bytes[3]}");

    Console.WriteLine($"get {Buffer.GetByte(numbers, 5u)}");
    Buffer.SetByte(numbers, 0u, (byte)0xFF);
    Console.WriteLine($"set {numbers[0] == 0x040302FF}");

    var pairs = new Pair[2];
    short[] shorts = [1, 2, 3, 4];
    Buffer.BlockCopy(shorts, 0u, pairs, 0u, Buffer.ByteLength(shorts));
    Console.WriteLine($"structs {Buffer.ByteLength(pairs)} {pairs[1].Low} {pairs[1].High}");

    long[] wide = [0L, 0L];
    Buffer.MemoryCopy((void*)&numbers[1], (void*)&wide[1], 8u, 4u);
    Console.WriteLine($"memory {wide[1] == 0x08070605L}");
}

int Main()
{
    ShowMaking();
    ShowResizing();
    ShowCopying();
    ShowOrdering();
    ShowSearching();
    ShowBuffer();
    return 0;
}
