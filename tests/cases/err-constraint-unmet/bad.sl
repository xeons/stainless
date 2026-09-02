module Bad;

public interface Comparable<T> { int CompareTo(T other); }

public class Plain { int value; public Plain(int v) { value = v; } }

T Largest<T>(T[] values) where T : Comparable<T> { return values[0]; }

int Main() {
    Largest(new Plain[2]);
    return 0;
}
