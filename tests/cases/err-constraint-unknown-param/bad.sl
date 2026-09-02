module Bad;

public interface Shape { double Area(); }

public class Holder<T> where U : Shape { T item; }

int Main() {
    Holder<int> h;
    return 0;
}
