// What an array literal refuses.
//
// It has no type of its own, so every one of these is the same question:
// nothing here says what this should be, or what it is told does not fit.
module BadArrayLiterals;

void Take(int[] numbers) { }

public void Main() {
    // Nothing to infer from, and nothing to infer.
    var nothing = [];

    // An inline array is its elements, so the count is part of the type.
    int[3] wrong = [1, 2];

    // An array holds one type, and these two reach no common one.
    var mixed = [1, "two"];

    // The parameter says int, so the elements are checked against int rather
    // than the literal being reported as a whole.
    Take(["a", "b"]);

    // Not an array at all.
    int scalar = [1, 2];
}
