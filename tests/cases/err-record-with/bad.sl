// SPDX-License-Identifier: 0BSD
//
// The three ways a `with` can be wrong: a target that is not a record, a name
// the record does not have, and a name given twice.
module BadWith;

public record Point(int X, int Y);

public class Plain
{
    public int N;
    public Plain(int n) { N = n; }
}

int Main()
{
    var p = new Point(1, 2);

    // No such parameter.
    var missing = p with { Z = 3 };

    // The same one twice, where the second would quietly be the one that won.
    var twice = p with { X = 1, X = 2 };

    // Not a record at all: an ordinary class has no parameters to carry over.
    var plain = new Plain(1) with { N = 2 };

    return 0;
}
