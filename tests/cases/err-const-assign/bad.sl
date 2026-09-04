// SPDX-License-Identifier: 0BSD
module Bad;

int Main() {
    const int limit = 10;
    limit = 11;
    return 0;
}
