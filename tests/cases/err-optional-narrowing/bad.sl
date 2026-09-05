// What a null check does not prove.
//
// Each of these is the fact's lifetime rather than the fact: something between
// the check and the use could have changed what was checked, so the proof is
// dropped. The rules are the ones variants already followed -- one table, one
// set of answers.
module BadNarrowing;
public class Node { public int Value; public Node? Next; public Node(int v) { Value = v; } }

Node? Fresh() { return null; }

public void Main() {
    Node? x = new Node(1);

    // Reassigned inside the branch: the proof was about the old value.
    if (x != null) {
        x = Fresh();
        int bad = x.Value;
    }

    // A loop body that reassigns takes the proof away.
    Node? y = new Node(2);
    while (y != null) {
        y = Fresh();
        int alsoBad = y.Value;
    }

    // The else arm of != null knows nothing good.
    Node? z = new Node(3);
    if (z != null) { } else { int worse = z.Value; }

    // Weak cannot be checked at all.
    weak Node? w = new Node(4);
    if (w != null) { int nope = w.Value; }

    // A call result is not a name.
    if (Fresh() != null) { }
    int never = Fresh().Value;
}
