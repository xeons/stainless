module Bad;

public interface Shape { double Area(); }

public class Blob : Shape {
    double size;
    public Blob(double s) { size = s; }
}

int Main() { return 0; }
