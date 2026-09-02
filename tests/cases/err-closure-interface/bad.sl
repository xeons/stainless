// SPDX-License-Identifier: 0BSD
module Bad;

// Two methods, so there is no single one for a lambda to be.
public interface IPair {
    int First(int value);
    int Second(int value);
}

int Main() {
    IPair p = value => value;
    return p.First(1);
}
