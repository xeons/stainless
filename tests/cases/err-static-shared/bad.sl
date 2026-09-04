// SPDX-License-Identifier: 0BSD
module Bad;

// A library has no entry point, so nothing would ever run this.
static readonly int Limit = 64;

export "C" int GetLimit() { return Limit; }
