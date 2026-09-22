// SPDX-License-Identifier: 0BSD
//
// The six controls a Lazarus form has that the first three samples did not: a
// cool bar of draggable bands, a notebook with no tabs, a toggle button, a
// palette of speed buttons, a button with a picture, and the ok/cancel strip
// every dialog ends with.
//
//   stainless run samples/forms/buttons.sl forms/src bindings/win32/api \
//       bindings/win32/Win32.sl -l user32 -l gdi32 -l comctl32
//
// `--selftest` builds the same window, checks what it can without a person in
// front of it, and quits. What it cannot check is what the thing looks like --
// five of the six draw themselves, so a screenshot is the only real test and
// `forms/README.md` says how to take one.
module Buttons;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Forms;
import Forms.Drawing;
import Forms.Platform;

public class ButtonsForm : Form
{
    public CoolBar Bar;
    public CoolBand ToolsBand;
    public CoolBand ZoomBand;
    public ToolBar Tools;
    public ComboBox Zoom;

    public Notebook Pages;
    public NotebookPage FirstPage;
    public NotebookPage SecondPage;
    public NotebookPage ThirdPage;

    public ToggleButton Bold;
    public ToggleButton Italic;
    public Button Pictured;
    public SpeedButton Pen;
    public SpeedButton Brush;
    public SpeedButton Eraser;
    public Label Readout;

    public ButtonPanel Buttons;

    public int Presses;

    public ButtonsForm()
    {
        base(WindowBorder.Sizable);
        Text = "Buttons, bands and pages";
        SetBounds(0, 0, 640, 460);
        Presses = 0;

        // ---- a cool bar across the top, with two bands sharing one row.
        //
        // The controls are ordinary children of the bar; a band is a row entry
        // that points at one, which is exactly `TCoolBand.Control`.
        Bar = new CoolBar(this);
        Bar.Dock = DockStyle.Top;

        Tools = new ToolBar(Bar);
        Tools.Height = 26;
        Tools.Add("New");
        Tools.Add("Open");
        Tools.Add("Save");

        ToolsBand = new CoolBand(Bar);
        ToolsBand.Text = "Tools";
        ToolsBand.Control = Tools;
        ToolsBand.Width = 300;

        Zoom = new ComboBox(Bar);
        Zoom.Height = 24;
        Zoom.Add("50%");
        Zoom.Add("100%");
        Zoom.Add("200%");
        Zoom.SelectedIndex = 1;

        ZoomBand = new CoolBand(Bar);
        ZoomBand.Text = "Zoom";
        ZoomBand.Break = false;      // share the row with the band before it
        ZoomBand.Control = Zoom;
        ZoomBand.Width = 220;

        Bar.Height = Bar.PreferredSize.Height;

        // ---- the ok/cancel strip, docked to the bottom before the notebook
        // fills what is left.
        Buttons = new ButtonPanel(this);
        Buttons.ShowButtons = PanelButtons.Ok | PanelButtons.Cancel
                            | PanelButtons.Help;
        Buttons.Height = Buttons.PreferredSize.Height;
        Buttons.OkButton.Click += this.OnPressed;
        Buttons.CancelButton.Click += this.OnPressed;

        // ---- a notebook filling the middle. Three pages, no tabs: which one
        // shows is the program's business, which is the whole point of it.
        Pages = new Notebook(this);
        Pages.Dock = DockStyle.Fill;

        FirstPage = new NotebookPage(Pages, "Toggles");
        SecondPage = new NotebookPage(Pages, "Palette");
        ThirdPage = new NotebookPage(Pages, "Finished");

        BuildToggles();
        BuildPalette();
        BuildLast();

        Pages.SelectedIndex = 0;
    }

    void BuildToggles()
    {
        var explain = new Label(FirstPage);
        explain.SetBounds(12, 12, 400, 20);
        explain.Text = "A toggle button is a check box that stays pressed in.";

        Bold = new ToggleButton(FirstPage);
        Bold.Text = "Bold";
        Bold.SetBounds(12, 40, 70, 28);
        Bold.CheckedChanged += this.OnStyleChanged;

        Italic = new ToggleButton(FirstPage);
        Italic.Text = "Italic";
        Italic.SetBounds(90, 40, 70, 28);
        Italic.CheckedChanged += this.OnStyleChanged;

        Readout = new Label(FirstPage);
        Readout.SetBounds(12, 78, 400, 20);
        Readout.Text = "plain";

        // A picture on an ordinary button. There is no bitmap to hand here, so
        // this is the API being exercised rather than a picture being shown --
        // `Image = null` is the state a button starts in, and setting it back
        // is what a program clearing one does.
        Pictured = new Button(FirstPage);
        Pictured.Text = "With room for a picture";
        Pictured.SetBounds(12, 110, 200, 30);
        Pictured.ImageAlign = ImageAlignment.Left;
        Pictured.ImageSpacing = 6;
        Pictured.Click += this.OnPressed;

        var next = new Button(FirstPage);
        next.Text = "Next page";
        next.SetBounds(12, 152, 110, 28);
        next.Click += this.OnNext;
    }

    void BuildPalette()
    {
        var explain = new Label(SecondPage);
        explain.SetBounds(12, 12, 400, 20);
        explain.Text = "Speed buttons: no windows, one group, one stays down.";

        Pen = MakeTool("Pen", 12);
        Brush = MakeTool("Brush", 78);
        Eraser = MakeTool("Eraser", 144);
        Pen.Down = true;

        var next = new Button(SecondPage);
        next.Text = "Next page";
        next.SetBounds(12, 90, 110, 28);
        next.Click += this.OnNext;
    }

    SpeedButton MakeTool(String caption, int left)
    {
        var made = new SpeedButton(SecondPage);
        made.Text = caption;
        made.SetBounds(left, 40, 62, 30);
        made.GroupIndex = 1;
        made.Flat = true;
        made.Click += this.OnPressed;
        return made;
    }

    void BuildLast()
    {
        var explain = new Label(ThirdPage);
        explain.SetBounds(12, 12, 400, 20);
        explain.Text = "The last page. Nothing showed a tab to get here.";

        var back = new Button(ThirdPage);
        back.Text = "Back to the start";
        back.SetBounds(12, 40, 140, 28);
        back.Click += this.OnFirst;
    }

    void OnStyleChanged(Control sender)
    {
        var said = "plain";
        if (Bold.Checked && Italic.Checked)
        {
            said = "bold italic";
        }
        else if (Bold.Checked)
        {
            said = "bold";
        }
        else if (Italic.Checked)
        {
            said = "italic";
        }
        Readout.Text = said;
    }

    void OnPressed(Control sender) => Presses = Presses + 1;

    void OnNext(Control sender)
    {
        Pages.SelectedIndex = Pages.SelectedIndex + 1;
    }

    void OnFirst(Control sender) => Pages.SelectedIndex = 0;

    public bool SelfTest()
    {
        bool ok = true;

        // ---- the cool bar.
        //
        // Two bands sharing a row is the thing worth checking: the second says
        // `Break = false`, so the layout pass must put it beside the first and
        // not under it.
        ok = Check(ok, "a cool bar holds its bands", Bar.BandCount == 2);
        ok = Check(ok, "and lays two on one row",
                   ToolsBand.Top == ZoomBand.Top && ZoomBand.Left > ToolsBand.Left);
        ok = Check(ok, "and gives the row a height",
                   ToolsBand.Height > 0 && ToolsBand.Height == ZoomBand.Height);
        ok = Check(ok, "and stretches the last band of a row to the edge",
                   ZoomBand.DrawnWidth >= ZoomBand.Width);
        ok = Check(ok, "and puts each band's control past its grab handle",
                   Tools.Left > ToolsBand.Left && Zoom.Left > ZoomBand.Left);
        ok = Check(ok, "and asks for a height that fits the rows",
                   Bar.PreferredSize.Height >= ToolsBand.Height);

        // A band told to break takes a row of its own, and every band after it
        // in that row comes with it.
        ZoomBand.Break = true;
        ok = Check(ok, "a break puts a band on the next row",
                   ZoomBand.Top > ToolsBand.Top);
        ZoomBand.Break = false;
        ok = Check(ok, "and clearing it puts the band back",
                   ZoomBand.Top == ToolsBand.Top);

        // A band narrower than its minimum is widened to it, which is the one
        // rule `Width` enforces.
        ZoomBand.MinWidth = 150;
        ZoomBand.Width = 40;
        ok = Check(ok, "a band is never narrower than its minimum",
                   ZoomBand.Width == 150);
        ZoomBand.Width = 220;

        // Hiding a band takes it out of the layout and out of the hit-testing,
        // and takes its control with it.
        ZoomBand.Visible = false;
        ok = Check(ok, "hiding a band hides its control", !Zoom.Visible);
        ZoomBand.Visible = true;
        ok = Check(ok, "and showing it brings it back",
                   Zoom.Visible && ZoomBand.Top == ToolsBand.Top);

        // ---- the notebook.
        ok = Check(ok, "a notebook holds its pages", Pages.PageCount == 3);
        ok = Check(ok, "and shows the first",
                   Pages.SelectedIndex == 0 && FirstPage.Visible);
        ok = Check(ok, "and hides the rest",
                   !SecondPage.Visible && !ThirdPage.Visible);
        ok = Check(ok, "and fills itself with the one showing",
                   FirstPage.Width == Pages.ClientBounds.Width
                   && FirstPage.Height == Pages.ClientBounds.Height);

        Pages.SelectedIndex = 1;
        ok = Check(ok, "choosing a page swaps which is visible",
                   SecondPage.Visible && !FirstPage.Visible);
        ok = Check(ok, "and lays the new one out",
                   SecondPage.Width == Pages.ClientBounds.Width);
        ok = Check(ok, "a page can be found by name",
                   Pages.FindPage("Finished") == ThirdPage);
        ok = Check(ok, "and an index past the end is clamped, not an error",
                   ClampsTo(9, 2) && ClampsTo(-4, 0));
        Pages.SelectedIndex = 0;

        // ---- the toggle buttons. A toggle is a check box, so the state comes
        // back from the platform rather than from a field here.
        ok = Check(ok, "a toggle button starts up", !Bold.Checked);
        Bold.Checked = true;
        ok = Check(ok, "and reads back from the platform", Bold.Checked);

        // **A programmatic set raises nothing**, on either backend and on
        // purpose -- see the note on `CheckBox.Checked`. So the change event is
        // driven the way a click drives it, which is also the only way to test
        // the handler at all with nobody in front of the window.
        ok = Check(ok, "and a set alone raises no change", Readout.Text == "plain");
        Bold.OnPlatformValueChanged();
        ok = Check(ok, "and a click on it does", Readout.Text == "bold");

        Italic.Checked = true;
        ok = Check(ok, "two of them are not a group",
                   Bold.Checked && Italic.Checked);
        Italic.OnPlatformValueChanged();
        ok = Check(ok, "and both show", Readout.Text == "bold italic");

        Bold.Checked = false;
        Italic.Checked = false;
        Bold.OnPlatformValueChanged();
        ok = Check(ok, "and both go back up", Readout.Text == "plain");

        // ---- a picture on a button. Setting one and clearing it must both go
        // through to the platform without the button losing its caption, which
        // is the whole failure mode `BS_BITMAP` has.
        Pictured.Image = null;
        ok = Check(ok, "a button with no picture keeps its caption",
                   Pictured.Text == "With room for a picture");
        ok = Check(ok, "and remembers where a picture would go",
                   Pictured.ImageAlign == ImageAlignment.Left
                   && Pictured.ImageSpacing == 6);

        // ---- the speed buttons, which have no windows at all.
        ok = Check(ok, "a speed button is laid out",
                   Pen.Width == 62 && Pen.Height == 30);
        ok = Check(ok, "and one of the group is down",
                   Pen.Down && !Brush.Down && !Eraser.Down);
        ok = Check(ok, "and is drawn as pressed",
                   Pen.State == ButtonState.Down);

        Brush.Down = true;
        ok = Check(ok, "pressing another raises the first",
                   Brush.Down && !Pen.Down);
        ok = Check(ok, "and the raised one is drawn up",
                   Pen.State == ButtonState.Up);

        // Clicking the one that is down leaves it down, because the group is
        // not allowed to be empty -- which is `AllowAllUp` being false.
        int wasPressed = Presses;
        Brush.PerformClick();
        ok = Check(ok, "clicking the one that is down leaves it down",
                   Brush.Down);
        ok = Check(ok, "and still reaches the handler",
                   Presses == wasPressed + 1);

        Brush.AllowAllUp = true;
        Brush.PerformClick();
        ok = Check(ok, "unless the group may be empty", !Brush.Down);
        Brush.AllowAllUp = false;
        Pen.Down = true;

        // The parent hit-tests and forwards, since the pointer never crosses a
        // window boundary for a control that has no window.
        wasPressed = Presses;
        SecondPage.OnPlatformMouseDown(MouseButton.Left,
                                       Point.FromXY(Eraser.Left + 5, Eraser.Top + 5),
                                       ModifierKeys.None);
        SecondPage.OnPlatformMouseUp(MouseButton.Left,
                                     Point.FromXY(Eraser.Left + 5, Eraser.Top + 5),
                                     ModifierKeys.None);
        ok = Check(ok, "a real press on a speed button reaches its handler",
                   Presses == wasPressed + 1);
        ok = Check(ok, "and moves the group", Eraser.Down && !Pen.Down);

        // ---- the button strip.
        ok = Check(ok, "a button panel docks to the bottom",
                   Buttons.Dock == DockStyle.Bottom);
        ok = Check(ok, "and shows what it was asked for",
                   Buttons.OkButton.Visible && Buttons.CancelButton.Visible
                   && Buttons.HelpButton.Visible && !Buttons.CloseButton.Visible);
        ok = Check(ok, "and puts help in the far corner",
                   Buttons.HelpButton.Left < Buttons.OkButton.Left
                   && Buttons.HelpButton.Left < Buttons.CancelButton.Left);
        ok = Check(ok, "and packs the rest against the right",
                   Buttons.CancelButton.Right <= Buttons.ClientBounds.Width
                   && Buttons.CancelButton.Right > Buttons.ClientBounds.Width / 2);

        // **The one thing this control exists for.** Windows puts OK before
        // Cancel and GNOME puts Cancel before OK, so the check is written
        // against whichever order the widget set said it wanted rather than
        // against a fixed one -- a test that pinned one would fail on the other
        // desktop and be right to.
        bool okFirst = Buttons.EffectiveOrder == ButtonOrder.CloseOkCancel;
        ok = Check(ok, "and in this desktop's order",
                   okFirst ? Buttons.OkButton.Left < Buttons.CancelButton.Left
                           : Buttons.CancelButton.Left < Buttons.OkButton.Left);
        ok = Check(ok, "which is the one the widget set asked for",
                   okFirst == (WidgetSet.Current.Name == "Win32"));

        Buttons.Order = ButtonOrder.CloseCancelOk;
        ok = Check(ok, "and an order set by hand overrides it",
                   Buttons.CancelButton.Left < Buttons.OkButton.Left);
        Buttons.Order = ButtonOrder.Default;

        Buttons.ShowButtons = PanelButtons.Ok;
        ok = Check(ok, "turning a button off hides it rather than freeing it",
                   !Buttons.CancelButton.Visible && Buttons.OkButton.Visible);
        Buttons.ShowButtons = PanelButtons.Ok | PanelButtons.Cancel
                            | PanelButtons.Help;
        ok = Check(ok, "and turning it back on keeps the same object",
                   Buttons.CancelButton.Visible);

        wasPressed = Presses;
        Buttons.OkButton.PerformClick();
        ok = Check(ok, "a strip button reaches its handler",
                   Presses == wasPressed + 1);

        // ---- and a resize, which is where a drawn control usually breaks: the
        // cool bar rewraps its rows and the notebook re-fills with its page.
        var startedAt = Bounds;
        SetBounds(startedAt.X, startedAt.Y, 420, 400);
        for (int i = 0; i < 6; i++)
            Application.DoEvents();
        ok = Check(ok, "a narrow bar wraps its bands onto two rows",
                   ZoomBand.Top > ToolsBand.Top);
        ok = Check(ok, "and the notebook's page follows the resize",
                   FirstPage.Width == Pages.ClientBounds.Width);

        SetBounds(startedAt.X, startedAt.Y, 640, 460);
        for (int i = 0; i < 6; i++)
            Application.DoEvents();
        ok = Check(ok, "and widening it puts them back on one",
                   ZoomBand.Top == ToolsBand.Top);

        return ok;
    }

    /// Sets the page index out of range and answers whether it landed where it
    /// should have. Separate because the check reads better than the two lines.
    bool ClampsTo(int asked, int wanted)
    {
        Pages.SelectedIndex = asked;
        return Pages.SelectedIndex == wanted;
    }

    bool Check(bool running, String what, bool passed)
    {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        return running && passed;
    }
}

int Main()
{
    Application.Initialize();
    var form = new ButtonsForm();

    bool testing = false;
    var arguments = Standard.Env.GetArguments();
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        if (arguments[i] == "--selftest")
            testing = true;
        // Which page to open on, so that a screenshot can be taken of one that
        // is not the first.
        if (arguments[i] == "--page" && i + 1u < arguments.Length)
        {
            var which = Standard.Convert.ToInt(arguments[i + 1u]);
            if (which.Ok)
                form.Pages.SelectedIndex = which.Value;
        }
    }

    if (testing)
    {
        Console.WriteLine("Forms for Stainless -- bands, pages and buttons");
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
