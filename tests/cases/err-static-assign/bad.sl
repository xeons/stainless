// SPDX-License-Identifier: 0BSD
module Bad;

static readonly int Limit = 64;

int Main() {
    Limit = 128;        // every static is readonly
    return Limit;
}
