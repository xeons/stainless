// SPDX-License-Identifier: 0BSD
//
// A static class has no instances, so every member reached through one is a
// member that could never be reached -- and there is nothing to make one of.
module Bad;

public static class Holder {
    // Each of these needs an instance.
    int field;
    public Holder() { }
    ~Holder() { }
    public int Read() { return 1; }
    public int Value { get { return 1; } }

    // And this one is refused for a different reason: an automatic property
    // needs storage with an initializer, and a static has no other moment at
    // which to be given a first value.
    public static int Count { get; set; }
}

int Main() {
    var h = new Holder();
    return 0;
}
