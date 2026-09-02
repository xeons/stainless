module Bad;

public interface Shape { double Area(); }

public class Square : Shape {
    public int Area() { return 1; }     // wrong return type
}

int Main() { return 0; }
