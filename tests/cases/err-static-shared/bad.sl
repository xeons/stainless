// SPDX-License-Identifier: 0BSD
module Bad;

// A library has no entry point, so nothing would ever run this.
//
// **A String and not a number.** A static whose value is a constant is written
// onto the global itself and needs nothing to run it, so `= 64` is allowed here
// now; a string literal is an object something has to make, which is where the
// rule draws its line.
static readonly String Name = "library";

// Allowed, and here to say so: this one is a constant and the global is born
// holding it.
static readonly int Limit = 64;

export "C" int GetLimit() { return Limit + (int)Name.ByteLength(); }
