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
import Forms.Drawing;
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

    private void OnGreetItem(MenuItem sender) => OnGreet(_greet);

    private void OnExit(MenuItem sender) => Close();

    public bool SelfTest()
    {
        bool ok = true;
        _name.Text = "designer";
        _greet.PerformClick();
        ok = CheckSame("a click reaches the handler", "Hello, designer! (1)", _greeting.Text) && ok;
        ok = CheckSame("the title is the form file's", "Greeter", Text) && ok;
        ok = CheckSame("a nested control is parented", "True",
                       _greeting.Parent == _footer ? "True" : "False") && ok;

        // A menu item and a toolbar button, each added to what holds it.
        _greetItem.OnPlatformMenuClicked();
        ok = CheckSame("the menu's Greet reaches the handler", "Hello, designer! (2)", _greeting.Text) && ok;
        ok = CheckSame("the form's menu is the one the file names", "True",
                       Menu == _mainMenu ? "True" : "False") && ok;
        ok = CheckSame("and it holds its items in the file's order", "&Greet, -, E&xit",
                       DescribeMenuItems(_fileMenu)) && ok;
        _tools.OnPlatformToolClicked(_greetButton.Index);
        ok = CheckSame("the toolbar's Greet reaches the handler", "Hello, designer! (3)", _greeting.Text) && ok;

        // Embedded by the generated half, so it is here wherever this runs.
        var picture = _greet.Image;
        ok = CheckSame("the button's picture travels in the program", "16",
                       picture == null ? "none" : Standard.Text.FromInteger(((Bitmap)picture).Width)) && ok;
        return ok;
    }

    /// A heading's items, as their captions, with `-` for a separator.
    private String DescribeMenuItems(MenuItem heading)
    {
        var made = new StringBuilder();
        foreach (var item in heading.Items)
        {
            if (made.HasContent)
                made.Append(", ");
            made.Append(item.IsSeparator ? "-" : item.Text);
        }
        return made.ToText();
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
