// SPDX-License-Identifier: 0BSD
module Bad;

int Main() {
    switch (7) {
        case 1:  return 1;
        default: return 2;
        default: return 3;      // only one section can be the fallback
    }
}
