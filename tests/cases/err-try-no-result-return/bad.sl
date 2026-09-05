// SPDX-License-Identifier: 0BSD
module Bad;
import Standard.Convert;

// The failure has to go somewhere, and the only place is the caller. A
// function that does not return a Result has nowhere to put it.
int Main() {
    long n = try Convert.ToLong("1");
    return (int)n;
}
