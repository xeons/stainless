// SPDX-License-Identifier: 0BSD
//
// What a container cannot make is a compile error at the registration: an
// abstract class (SLC0126), two widest constructors (SLC0127), a parameter no
// provider can be asked for (SLC0128), and a default implementation that names
// no generic class (SLC0129).
module ErrDiConstruct;

import Standard.DependencyInjection;

public abstract class Shape
{
}

public sealed class Twice
{
    public Twice(Shape a) { }
    public Twice(Twice b) { }
}

public sealed class Counted
{
    public Counted(int start) { }
}

[DefaultImplementation("ErrDiConstruct.Nowhere")]
public interface IMissing<T>
{
}

public sealed class WantsMissing
{
    public WantsMissing(IMissing<int> missing) { }
}

public int Main()
{
    var services = new ServiceCollection();
    services.AddSingleton<Shape>();
    services.AddSingleton<Twice>();
    services.AddSingleton<Counted>();
    services.AddSingleton<WantsMissing>();
    return 0;
}
