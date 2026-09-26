// SPDX-License-Identifier: 0BSD
module SharedReader;

// The same variable, declared again, as a second C file would.
extern "C" int shared_total;

public void BumpFromReader() => shared_total++;
