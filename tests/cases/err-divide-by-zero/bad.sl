// SPDX-License-Identifier: 0BSD
module Bad;

const int None = 0;

int Divided() => 10 / 0;
int Remained() => 10 % 0;

// A named constant is just as knowable.
int ByConstant() => 10 / None;

int Main() => 0;
