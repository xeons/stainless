// SPDX-License-Identifier: 0BSD
module Bad;

class Counter {
    int value;
    public Counter() { value = 0; }
    public void Bump() { value = value + 1; }
}

int Main() {
    var counter = new Counter();
    parallel {
        // Two threads reaching one unsynchronized object.
        spawn counter.Bump();
    }
    return 0;
}
