module Bad;

public interface IShape { double Area(); }

public class Blob : IShape {
    double size;
    public Blob(double s) { size = s; }
}

int Main() { return 0; }
