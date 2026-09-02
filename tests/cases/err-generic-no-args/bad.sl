module Bad;

public class Box<T> { T value; }

int Main() {
    Box b;              // needs a type argument
    return 0;
}
