// SPDX-License-Identifier: 0BSD
module Bad;

public interface INamed
{
    // A default accessor may have a body, but an interface has no state, so
    // there is no storage for 'field' to name.
    String Name { get => field; }
}

public abstract class Shape
{
    // An abstract accessor is the one a derived class writes.
    public abstract double Area { get { return 0.0; } }
}

int Main() => 0;
