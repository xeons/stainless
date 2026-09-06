// SPDX-License-Identifier: 0BSD
//
// `threadsafe` says that operations on a type synchronize themselves. A type
// with no operations promises nothing by carrying it, so the word is refused
// there rather than accepted and ignored.
module Bad;

import Standard.Collections;

public threadsafe enum Level { Low, High }

public threadsafe variant Shape {
    Circle(double Radius);
    Empty;
}

public threadsafe delegate void Notify(int value);

// And the constraint, unmet.
long Counted<T>(T shared) where T : threadsafe { return 1; }

int Main() {
    var items = new List<int>();
    return (int)Counted(items);
}
