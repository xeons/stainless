// What a collection expression refuses.
//
// A '..' spreads what foreach would walk, into an element type its elements
// fit; an inline array has to know its length now; and a class has to be
// something that can be added to.
module BadCollectionExpressions;

/// Can be made, and has nothing to add with.
class Sealed
{
}

/// Has Add, and nothing that makes one without arguments.
class Needy
{
    public Needy(int size) { }

    public void Add(int item) { }
}

public void Main()
{
    int[] numbers = [1, 2, 3];

    // An int is not walked.
    int[] spread = [..5];

    // These yield ints.
    String[] words = [..numbers];

    // An array's length is not known until it runs.
    int[4] fixedLength = [..numbers, 4];

    // An inline array's length is known, and it is two where three are wanted.
    int[2] pair = [1, 2];
    int[3] tooShort = [..pair];

    Sealed nothingToAdd = [1];
    Needy nothingToMake = [1];
}
