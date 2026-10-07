// SPDX-License-Identifier: 0BSD
//
// What a constant expression refuses: a value its type cannot hold, which a
// run-time value would wrap; a value that depends on itself; and a division by
// zero worked out rather than written.
module ErrConstExpressions;

const int Overflows = 2147483647 + 1;               // SLT0093
const uint BelowZero = 0u - 1u;                     // SLT0093

const int Circular = Around + 1;                    // SLT0094
const int Around = Circular + 1;

// An enum member may name the members before it, and this names the one after.
enum Order { First = Order.Second, Second = 1 }     // SLT0094

const int Divides = 10 / (5 - 5);                   // SLT0040

int Main() => 0;