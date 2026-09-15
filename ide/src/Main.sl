// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// An IDE for Stainless, written in Stainless.
//
//   stainless-ide                 open with nothing in it
//   stainless-ide path/to/file.sl open that
//   stainless-ide --selftest      build the window, check what can be checked
module Ide;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Standard.Env;
import Forms;
import Forms.Platform;
import Ide.Editor;
import Ide.App;

int Main()
{
    Application.Initialize();
    var window = new Shell();

    bool testing = false;
    var arguments = Env.Arguments();
    // From zero: `Env.Arguments` is what `Main(String[] args)` would have been
    // handed, which does not include the program's own name.
    //
    // Every path named gets a tab, in the order they were given, and the first
    // one stays in front -- which is what a shell expanding `*.sl` means, and
    // what `ide a.sl b.sl` means too.
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        String argument = arguments[i];
        if (argument == "--selftest")
        {
            testing = true;
            continue;
        }
        if (argument.StartsWith("-"))
            continue;
        if (!window.OpenFile(argument))
        {
            Console.WriteLine("could not read " + argument);
        }
    }
    window.ShowFirstTab();

    if (testing)
    {
        Console.WriteLine("the Stainless IDE -- self test");
        window.Show();
        for (int i = 0; i < 20; i++)
            Application.DoEvents();
        bool ok = window.SelfTest();
        Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
        return ok ? 0 : 1;
    }

    window.CenterOnScreen();
    window.Show();
    Application.Run();
    return 0;
}
