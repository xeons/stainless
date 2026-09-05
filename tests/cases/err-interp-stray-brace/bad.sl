// SPDX-License-Identifier: 0BSD
module Bad;

// A lone `}` closes nothing. `}}` is how a literal brace is written, and a `}`
// on its own is far more often the end of a hole that was never opened.
int Main() {
    String written = $"stray } brace";
    return (int)written.ByteLength();
}
