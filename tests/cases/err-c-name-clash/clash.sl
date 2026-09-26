// SPDX-License-Identifier: 0BSD
module Clash;

// C has no overloading, so a second export under one name is a second
// function in one symbol.
export "C" int Twin(int x) => x;
export "C" int Twin(double x) => 1;

// A runtime function is defined in every program already.
export "C" void sl_retain(int x) { }

int Main() => 0;
