// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Collections;

// Reachable from every thread, and nothing synchronizes it.
static readonly List<int> Registry = new List<int>();

int Main() { return (int)Registry.Count(); }
