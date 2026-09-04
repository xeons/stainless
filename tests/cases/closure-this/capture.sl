// SPDX-License-Identifier: 0BSD
//
// A lambda written inside a method can reach the object it was written in. The
// member is captured by value, like everything else a lambda captures, so the
// closure holds what the member said at the time rather than a route back.
module Capture;

import Standard.Console;

interface IMap { int Apply(int x); }

class Scaler {
    public int Factor;
    public int Offset { get; set; }

    public Scaler(int factor, int offset) { Factor = factor; Offset = offset; }

    int Triple(int n) { return n * 3; }

    public IMap ByField()     { return x => x * Factor; }
    public IMap ByProperty()  { return x => x + Offset; }
    public IMap ByThis()      { return x => x * this.Factor; }
    public IMap ByMethod()    { return x => Triple(x); }
    public IMap ByThisCall()  { return x => this.Triple(x) + this.Factor; }
    public IMap Nested()      { return x => Wrap(x); }

    int Wrap(int n) { return n + Factor; }

    // Captured by value: changing the field afterwards does not change what the
    // closure already took.
    public IMap Snapshot() { return x => x + Factor; }
}

int Main() {
    var scaler = new Scaler(3, 5);

    Console.WriteLine(Text.FromInteger(scaler.ByField().Apply(7)));
    Console.WriteLine(Text.FromInteger(scaler.ByProperty().Apply(7)));
    Console.WriteLine(Text.FromInteger(scaler.ByThis().Apply(7)));
    Console.WriteLine(Text.FromInteger(scaler.ByMethod().Apply(7)));
    Console.WriteLine(Text.FromInteger(scaler.ByThisCall().Apply(7)));
    Console.WriteLine(Text.FromInteger(scaler.Nested().Apply(7)));

    var taken = scaler.Snapshot();
    scaler.Factor = 100;
    Console.WriteLine(Text.FromInteger(taken.Apply(0)));

    return 0;
}
