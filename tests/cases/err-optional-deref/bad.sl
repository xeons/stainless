module Bad;

class Node {
    int id;
    Node? next;
    Node(int n) { id = n; }
    public int Peek() { return next.id; }   // next may be null
}

int Main() { return 0; }
