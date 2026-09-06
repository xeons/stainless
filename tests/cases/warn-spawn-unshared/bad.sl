// SPDX-License-Identifier: 0BSD
//
// Handing an unsynchronized object to another thread. It warns and compiles.
//
// A refusal was tried and is wrong: `threadsafe` is an assertion about a type's
// body, so its absence is only the absence of an assertion, and refusing on
// that leaves a programmer who knows better with nothing to do but write the
// word untruthfully. A lie is worse than a warning -- it is permanent, it is
// invisible at the call site, and it covers the next mistake too.
module Bad;

import Standard.Collections;

extern "C" int printf(byte* format, ...);

class Counter {
    int value;
    public Counter() { value = 0; }
    public void Bump() { value = value + 1; }
    public int Value() { return value; }
}

// A variant's own fields are a tag and a blob of bytes. What it really holds is
// whatever case is in it, and one of these holds a List.
variant Payload {
    Plain(int Count);
    Held(List<int> Items);
}

int Taken(Payload payload) {
    switch (payload) {
        case Plain plain: return plain.Count;
        default: return -1;
    }
}

int Main() {
    var counter = new Counter();
    parallel {
        // One thread reaching an object another thread also holds. Warned
        // about, and left to the author, who can see that nothing else runs.
        spawn counter.Bump();
    }
    printf("counter=%d\n", counter.Value());

    Payload payload = Payload.Plain(1);
    parallel {
        spawn Taken(payload);
    }
    printf("payload=%d\n", Taken(payload));

    return 0;
}
