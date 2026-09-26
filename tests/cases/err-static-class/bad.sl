// SPDX-License-Identifier: 0BSD
//
// A static class has no instances, so every member reached through one is a
// member that could never be reached -- and there is nothing to make one of.
module Bad;

public static class Holder
{
    // Each of these needs an instance.
    int _field;
    public Holder() { }
    ~Holder() { }
    public int Read() => 1;
    public int Value { get { return 1; } }

    // Static storage, which a static class may have.
    public static int Count { get; set; }
}

int Main()
{
    var h = new Holder();
    return 0;
}
