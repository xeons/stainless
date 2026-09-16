// SPDX-License-Identifier: 0BSD
module Bad;

// A type is named here by its name alone, so these two collide. C# tells them
// apart by type-parameter count as well; nothing here does.
//
// **This used to crash the compiler rather than say so.** The error below was
// reported, the non-generic declaration was skipped without a symbol, and the
// members pass then went looking for it under a name the template had taken.
public class Work<T>
{
    public Work(T value) { }
}

public class Work
{
    public Work() { }
}

int Main() => 0;
