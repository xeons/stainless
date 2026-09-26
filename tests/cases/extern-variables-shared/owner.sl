// SPDX-License-Identifier: 0BSD
module SharedOwner;

// Defined here, under a name C can reach.
export "C" int shared_total = 40;

public int ReadFromOwner() => shared_total;
