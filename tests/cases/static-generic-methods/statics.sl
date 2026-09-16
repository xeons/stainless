// SPDX-License-Identifier: 0BSD
//
// A generic method on a type, reached without an instance.
//
// **None of this worked, and each part failed differently.** `Helper.Take(...)`
// was not recognised as a static call at all, because a generic method is a
// template and the lookup that decides only sees methods -- so the type name
// was bound as though it were a value and the error was that `Helper` did not
// exist. Instantiating one then gave it a `this` parameter it has no instance
// for, and dropped `IsStatic` on the way, so the one call shape that fits was
// refused as needing an object. And a plain overload beside a generic one
// answered for every call, because the generic sibling was consulted only when
// there were no overloads at all rather than when none of them fitted.
module StaticGenerics;

import Standard.Console;
import Standard.Text;

public interface IProduce<T> { T Produce(); }
public interface IConsume<T> { void Consume(T value); }
public closure void Action();

public static class Helper
{
    /// Inferred from the closures: neither the type argument nor the parameter
    /// types are written at the call.
    public static void Run<T>(IProduce<T> work, IConsume<T> then) => then.Consume(work.Produce());

    /// The same name without type parameters. Which one a call means is
    /// decided by whether the arguments fit, not by which was declared.
    public static void Run(Action work, Action then)
    {
        work();
        then();
    }

    public static T Echo<T>(T value) => value;
}

/// A generic method on an ordinary class, called on an instance, which is the
/// shape that already worked and is here so a regression shows up as a
/// difference rather than as silence.
public class Holder
{
    public T Twice<T>(IProduce<T> work)
    {
        work.Produce();
        return work.Produce();
    }
}

int Main()
{
    int factor = 6;

    Helper.Run(() => factor * 7, v => Console.WriteLine("generic " + FromInteger(v)));
    Helper.Run(() => Console.WriteLine("plain work"), () => Console.WriteLine("plain then"));

    Console.WriteLine("echo " + FromInteger(Helper.Echo(11)));
    Console.WriteLine("echo " + Helper.Echo("text"));

    var holder = new Holder();
    Console.WriteLine("instance " + FromInteger(holder.Twice(() => factor)));

    return 0;
}
