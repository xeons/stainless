// SPDX-License-Identifier: 0BSD
module Bad;

public class Base { int value; }

// Only interfaces may constrain a type parameter.
public class Holder<T> where T : Base { T item; }

int Main() {
    Holder<Base> h;
    return 0;
}
