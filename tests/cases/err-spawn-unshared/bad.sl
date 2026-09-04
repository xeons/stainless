// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Collections;

class Counter {
    int value;
    public Counter() { value = 0; }
    public void Bump() { value = value + 1; }
}

// A variant's own fields are a tag and a blob of bytes. What it really holds is
// whatever case is in it, and one of these holds a List.
variant Payload {
    Plain(int Count);
    Held(List<int> Items);
}

void Take(Payload payload) { }

int Main() {
    var counter = new Counter();
    parallel {
        // Two threads reaching one unsynchronized object.
        spawn counter.Bump();
    }

    Payload payload = Payload.Plain(1);
    parallel {
        spawn Take(payload);
    }
    return 0;
}
