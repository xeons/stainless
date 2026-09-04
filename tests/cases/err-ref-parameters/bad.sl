// SPDX-License-Identifier: 0BSD
module Bad;

public struct Point { public double X; public double Y; }
public interface IAdjust { void Adjust(ref int n); }

// The mode is part of the signature, so this does not implement it.
public class Wrong : IAdjust { public void Adjust(int n) { } }

void Bump(ref int n) { }
void Reads(in Point p) { }
int Value() { return 1; }

// An `in` parameter is the caller's storage and promises not to be written.
void WritesIn(in int n) { n = 5; }
void WritesInField(in Point p) { p.X = 1.0; }
void PassesInOnwards(in Point p) { Takes(ref p); }
void Takes(ref Point p) { }

int Main() {
    int k = 0;

    Bump(k);                    // the call has to say 'ref' too
    Bump(ref Value());          // nothing to take the address of
    Reads(ref k);               // 'in' is not passed with 'ref'

    const int c = 1;
    Bump(ref c);                // a const cannot be written

    double d = 0.0;
    Bump(ref d);                // a 'ref' argument is not converted

    parallel { spawn Bump(ref k); }   // a job would share the caller's storage
    return 0;
}
