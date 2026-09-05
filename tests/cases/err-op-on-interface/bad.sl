// SPDX-License-Identifier: 0BSD
module Bad;

// An operator is chosen from the operand types where it is written rather than
// dispatched through a receiver, so an interface has nothing to promise here.
public interface IAddable {
    public static IAddable operator +(IAddable a, IAddable b) { return a; }
}

int Main() { return 0; }
