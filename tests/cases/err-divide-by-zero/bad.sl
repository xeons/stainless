// SPDX-License-Identifier: 0BSD
module Bad;

const int None = 0;

int Divided() { return 10 / 0; }
int Remained() { return 10 % 0; }

// A named constant is just as knowable.
int ByConstant() { return 10 / None; }

int Main() { return 0; }
