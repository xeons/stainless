// SPDX-License-Identifier: 0BSD
module Bad;

// `&&` short-circuits, and an overload would have to evaluate both sides to be
// called at all -- so overloading it would change what the operator means
// rather than what it does.
public struct Flag {
    public bool Value;
    public static Flag operator &&(Flag a, Flag b) { return a; }
}

int Main() { return 0; }
