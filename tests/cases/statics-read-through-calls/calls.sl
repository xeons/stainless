// SPDX-License-Identifier: 0BSD
//
// An initializer that reads a static through a call runs after it, as one
// naming it does: through a function, a constructor and a closure.
module ThroughCalls;

import Standard.Console;

public class Label
{
    public String Text;
    public Label() => Text = Settings.Suffix + "?";
}

public static class Settings
{
    public static String Called = Describe();
    public static Label Constructed = new Label();
    public static String Closed = Apply((String given) => given + Suffix);

    public static String Suffix = "late";

    static String Describe() => Suffix + "!";
    static String Apply(Func<String, String> make) => make("closed-");
}

public int Main()
{
    Console.WriteLine(Settings.Called);
    Console.WriteLine(Settings.Constructed.Text);
    Console.WriteLine(Settings.Closed);
    return 0;
}
