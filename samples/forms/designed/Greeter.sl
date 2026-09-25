// SPDX-License-Identifier: 0BSD
//
// The half of a designed form that a person writes: the constructor, the
// handlers, and whatever the form keeps. The controls and the code that builds
// them are the other half, Greeter.designer.sl, generated from Greeter.slfm:
//
//   slforms samples/forms/designed
//
// `--selftest` builds the window, presses the button, and checks the answer.
module Greeter;

import Standard.Console;
import Standard.Env;
import Standard.Text;
import Forms;
import Forms.Platform;

public class GreeterForm
{
    private int _greetings;

    public GreeterForm()
    {
        base(WindowBorder.Sizable);
        InitializeComponent();
        _greetings = 0;
    }

    private void OnGreet(Control sender)
    {
        _greetings++;
        _greeting.Text = "Hello, " + _name.Text + "! (" + Standard.Text.FromInteger(_greetings) + ")";
    }

    public bool SelfTest()
    {
        bool ok = true;
        _name.Text = "designer";
        _greet.PerformClick();
        ok = CheckSame("a click reaches the handler", "Hello, designer! (1)", _greeting.Text) && ok;
        ok = CheckSame("the title is the form file's", "Greeter", Text) && ok;
        ok = CheckSame("a nested control is parented", "True",
                       _greeting.Parent == _footer ? "True" : "False") && ok;
        return ok;
    }

    private bool CheckSame(String what, String expected, String actual)
    {
        bool passed = expected == actual;
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        if (!passed)
            Console.WriteLine("         expected '" + expected + "', got '" + actual + "'");
        return passed;
    }
}

int Main()
{
    Application.Initialize();
    var form = new GreeterForm();

    var arguments = Env.GetArguments();
    if (arguments.Length > 0u && arguments[0u] == "--selftest")
    {
        Console.WriteLine("Forms for Stainless -- a designed form");
        form.Show();
        for (int i = 0; i < 20; i++)
            Application.DoEvents();
        bool ok = form.SelfTest();
        Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
        return ok ? 0 : 1;
    }

    form.CenterOnScreen();
    form.Show();
    Application.Run();
    return 0;
}
