// SPDX-License-Identifier: 0BSD
module Bad;

// Read through a call, a static reaching itself is the same cycle as one
// naming itself: no order gives it a value first.
static readonly String Greeting = Describe();

String Describe() => Greeting + "!";

int Main() => (int)Greeting.ByteLength();
