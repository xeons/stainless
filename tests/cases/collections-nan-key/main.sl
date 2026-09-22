// NaN as a key.
module Main;

import Standard.Console;
import Standard.Collections;
import Standard.Text;

void Say(String what, bool passed)
{
    Console.WriteLine((passed ? "ok   " : "FAIL ") + what);
}

int Main()
{
    double nan = 0.0 / 0.0;
    var map = new Dictionary<double, int>();
    map.Set(nan, 1);
    map.Set(nan, 2);
    Say("NaN is one key", map.Count == 1u && map.ContainsKey(nan) && map.GetOr(nan, 0) == 2);
    Say("and can be removed", map.Remove(nan) && map.Count == 0u);

    var set = new HashSet<double>();
    set.Add(nan);
    set.Add(nan);
    set.Add(0.0);
    set.Add(-0.0);
    Say("a set holds one NaN and one zero", set.Count == 2u);

    Say("NaN equals itself by EqualTo", nan.EqualTo(nan));
    Say("but not by ==", !(nan == nan));
    return 0;
}
