// SPDX-License-Identifier: 0BSD
module Bad;

// `out` is a promise the callee makes and the caller reads, so both halves are
// checked: the callee has to write it on every path, and the call has to say
// `out` so a reader knows the variable may come back different.

void NeverWrites(out int x) { }

void OnlyOneArm(bool flag, out int x) {
    if (flag) { x = 1; }
}

bool ReturnsEarly(int n, out int half) {
    if (n % 2 != 0) { return false; }
    half = n / 2;
    return true;
}

void Fine(bool flag, out int x) {
    if (flag) { x = 1; } else { x = 2; }
}

void Takes(ref int byRef) { byRef = 1; }

int Main() {
    int n = 0;

    // The call has to say `out` too.
    Fine(true, n);

    // And must not say it where the parameter is something else.
    Takes(out n);

    // A literal has no storage to write back to.
    Fine(true, out 5);
    return 0;
}
