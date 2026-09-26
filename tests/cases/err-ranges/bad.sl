// What `^n` and `a..b` refuse.
//
// Counting from the end needs an end, and a range needs something that can
// hand back part of itself.
module BadRanges;

/// Counts, but is not indexed by anything.
class Counted
{
    public nuint Count => 3u;
}

/// Neither counts nor is indexed.
class Plain
{
}

public void Main()
{
    int[] numbers = [1, 2, 3];
    int[3] inline = [1, 2, 3];
    int* pointer = null;
    var counted = new Counted();
    var plain = new Plain();

    // A pointer has no length to count back from, and nor has this class.
    int fromPointer = pointer[^1];
    var fromPlain = plain[^1];

    // A count, and no indexer taking an integer.
    var fromCounted = counted[^1];

    // An inline array's length is its type, so these are known to be outside it.
    int past = inline[^4];
    int end = inline[^0];

    // A slice holds an array, and an inline array is not one; the class
    // declares no Slice.
    var part = inline[1..];
    var some = counted[0..1];

    // '^' and '..' count in integers.
    var text = ^"one";
    Range wrong = "one"..2;
}
