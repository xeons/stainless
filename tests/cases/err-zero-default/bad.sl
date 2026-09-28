// A type whose zero would hold a null in a never-null reference has no zero
// value, so `default` of one is refused: a struct holding an array, a class,
// and a `T` that turns out to be a `String` in the instantiation that says so.
module Bad;

public struct Holder
{
    public byte[] Data;
}

public class Node
{
    public Node()
    {
    }
}

T Blank<T>() => default(T);

int Main()
{
    Holder held = default(Holder);
    Node node = default;
    String text = Blank<String>();
    int number = Blank<int>();
    return number;
}
