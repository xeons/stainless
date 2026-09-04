// SPDX-License-Identifier: 0BSD
module Bad;

import Standard.Collections;

int Main() {
    var items = new List<int>();
    items.Add(1);

    // Every chunk would read the same unsynchronized list.
    parallel for (int i = 0; i < 10; i = i + 1) { items.Add(i); }
    return 0;
}
