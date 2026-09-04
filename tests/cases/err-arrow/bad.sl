// What `->` refuses. A '.' accepts all of these, which is the difference.
module ErrArrow;

public struct Point {
    public int X;
}

public class Box {
    public int Value;
}

int Main() {
    Point point;
    point.X = 1;

    // A value is not a pointer. This is the mistake the arrow exists to catch;
    // written with a dot it would simply be right.
    int a = point->X;                       // SL0494

    // A class reference is a pointer at runtime and not one in the language,
    // and the arrow follows the language.
    var box = new Box();
    int b = box->Value;                     // SL0494

    // A pointer to something with no members reaches nothing.
    int number = 7;
    int* counted = &number;
    int c = counted->X;                     // SL0494

    return a + b + c;
}
