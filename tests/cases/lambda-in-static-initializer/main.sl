// SPDX-License-Identifier: 0BSD
//
// A lambda in a static initializer calls a static method of its type by its
// bare name. There is no object to capture, and none is asked for.
module LambdaInStaticInitializer;

import Standard.Console;

public sealed class Holder
{
    private static Func<int> s_make = () => Make(3);

    private static Lazy<String> s_named = new Lazy<String>(() => Name("lazy"));

    private static int Make(int n) => n * 2;

    private static String Name(String text) => text + "!";

    public static String Show() => $"{s_make()} {s_named.Value}";
}

public int Main()
{
    Console.WriteLine(Holder.Show());
    return 0;
}
