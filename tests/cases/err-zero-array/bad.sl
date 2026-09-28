// `new T[n]` starts every element as the zero of `T`, so it is refused for a
// `T` with none, including one a template names. A length of the constant zero
// makes no element, and stays legal.
module Bad;

public class Node
{
    public Node()
    {
    }
}

T[] Room<T>(nuint count) => new T[count];

int Main()
{
    String[] words = new String[3];
    Node[] nodes = Room<Node>(2u);
    String[] none = new String[0];
    return 0;
}
