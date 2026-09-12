// A menu item and a toolbar button have to find their way back to a handler.
//
// Both arrive as `WM_COMMAND`, and neither carries anything that names the
// object that should run. A control's click is told apart by `lParam` holding
// its window handle; a *menu* command has `lParam` null and an id, which has to
// be resolved against the window's own menu tree -- including through submenus.
// A toolbar's buttons all share one window, so the id says which button rather
// than which control, and the bar resolves it against its own list.
//
// Three ways to get the same message wrong, none of which fails loudly: an
// unresolved id is simply a handler that never runs. So the ids are driven
// through `WM_COMMAND` here exactly as Windows would drive them, and what ran
// is printed.
module FormsMenus;

import Standard.Console;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
import Win32;
import Win32.Handles;
import Win32.User32;

#if WINDOWS

public class MenuForm : Form {
    public MenuItem Open;
    public MenuItem Nested;
    public MenuItem Heading;
    public ToolBar  Tools;
    public ToolButton First;
    public ToolButton Toggle;

    public MenuForm() {
        base(WindowBorder.Sizable);
        Text = "menus";
        SetBounds(0, 0, 500, 320);

        var bar = new MainMenu();
        var file = bar.Add("&File");
        Open = file.Add("&Open");
        Open.Click += this.OnOpen;

        // A heading with items under it. Choosing the heading itself does
        // nothing -- it opens the submenu -- and the item below it must still
        // be found, which is what makes the search recursive.
        Heading = file.Add("&Recent");
        Nested = Heading.Add("&Yesterday");
        Nested.Click += this.OnNested;
        Heading.Click += this.OnHeading;

        Menu = bar;

        Tools = new ToolBar(this);
        Tools.Dock = DockStyle.Top;
        First = Tools.Add("One");
        First.Click += this.OnFirst;
        Tools.Add("Two").Click += this.OnSecond;
        Toggle = Tools.AddToggle("Three", -1);
        Toggle.Click += this.OnThird;
    }

    void OnOpen(MenuItem sender)    { Console.WriteLine("menu: chose Open"); }
    void OnNested(MenuItem sender)  { Console.WriteLine("menu: chose a nested item"); }
    void OnHeading(MenuItem sender) { Console.WriteLine("menu: a heading RAN, and should not have"); }

    void OnFirst(Control sender)  { Console.WriteLine("toolbar: button 0 clicked"); }
    void OnSecond(Control sender) { Console.WriteLine("toolbar: button 1 clicked"); }
    void OnThird(Control sender) {
        Console.WriteLine("toolbar: button 2 clicked");
        Console.WriteLine("toolbar: a toggle reports its state: "
            + (Toggle.Checked ? "true" : "false"));
    }
}

void Settle() { for (int i = 0; i < 8; i += 1) { Application.DoEvents(); } }

/// Chooses a menu item the way Windows does: `WM_COMMAND` with the id in the
/// low word and a null `lParam`.
void ChooseMenu(HWND window, int id) {
    SendMessageW(window, WmCommand, (ulong)(uint)id, 0);
}

int Main() {
    Application.Initialize();
    var form = new MenuForm();
    form.Show();
    Settle();

    HWND window = (HWND)(void*)form.Handle;

    // The ids are the platform's, so they are asked for rather than assumed.
    ChooseMenu(window, (int)form.Open.PlatformId);
    Settle();
    ChooseMenu(window, (int)form.Nested.PlatformId);
    Settle();

    // A heading opens its submenu and raises nothing. Windows never sends a
    // command for one; sending it anyway proves the tree does not run it.
    ChooseMenu(window, (int)form.Heading.PlatformId);
    Settle();
    Console.WriteLine("menu: a heading raises nothing");

    // A toolbar button reports to the *parent*, naming itself in the low word
    // and the toolbar in `lParam`.
    HWND bar = (HWND)(void*)form.Tools.Handle;
    SendMessageW(window, WmCommand, (ulong)(uint)(int)form.First.PlatformId,
                 (long)(nuint)(void*)bar);
    Settle();

    form.Toggle.Checked = true;
    SendMessageW(window, WmCommand, (ulong)(uint)(int)form.Toggle.PlatformId,
                 (long)(nuint)(void*)bar);
    Settle();

    return 0;
}

#else

int Main() { return 0; }

#endif
