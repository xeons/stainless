// SPDX-License-Identifier: 0BSD
//
// What the controls promise about their own state: a selection that follows
// the page it named, a default button that is the only one, a range that stays
// a range, an event raised once for one change and not at all for none.
//
//   stainless run samples/forms/controls.sl forms/src bindings/win32 \
//       -l user32 -l gdi32 -l comctl32 -l comdlg32 -l ole32 -l shell32 -l advapi32
//
// `--selftest` builds the same window, drives each control the way the
// platform or a program would, and checks what it then says. A few checks ask
// the Win32 control itself, because the control layer's own answer is the one
// that was wrong; those are Windows only.
module ControlChecks;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if WINDOWS
import Win32;
import Win32.Handles;
import Win32.User32;
import Win32.ComCtl32;
#endif

/// A popup built the way `Show` builds one, without the modal wait -- so a
/// test can see what building it does to items it shares with a menu bar.
public class BuiltPopup : PopupMenu
{
    public BuiltPopup() => base();

    public void BuildAndDiscard()
    {
        var built = WidgetSet.Current.CreateMenu();
        RealiseInto(built);
        ForgetBuilt();
    }
}

public class ChecksForm : Form
{
    public MainMenu Bar;
    public MenuItem Shared;
    public BuiltPopup Popup;

    public TabControl Tabs;
    public TabPage TabOne;
    public TabPage TabTwo;
    public TabPage TabThree;

    public Notebook Book;
    public NotebookPage PageOne;
    public NotebookPage PageTwo;
    public NotebookPage PageThree;
    public NotebookPage PageFour;

    public TextBox Notes;
    public RadioGroup Choice;
    public SpeedButton Loose;
    public SpeedButton Pen;
    public SpeedButton Brush;
    public Button Accept;
    public Button Refuse;

    public TrackBar Slider;
    public ProgressBar Gauge;
    public SpinEdit Count;
    public ScrollBar Scroller;

    public Panel Split;
    public Panel Side;
    public Panel Hidden;
    public Splitter Divide;
    public Panel Rest;

    public TreeView Tree;
    public ImageList Icons;

    public Panel Strip;
    public CoolBar Cool;
    public CoolBand First;
    public CoolBand Second;
    public CoolBand Third;
    public CoolBand Folded;
    public Label FoldedLabel;

    public int TabChanges;
    public int PageChanges;
    public int ChoiceChanges;
    public int CoolChanges;

    public ChecksForm()
    {
        base(WindowBorder.Sizable);
        Text = "Control checks";
        SetBounds(0, 0, 660, 620);

        BuildMenu();

        Tabs = new TabControl(this);
        Tabs.SetBounds(8, 8, 300, 110);
        TabOne = new TabPage(Tabs, "One");
        TabTwo = new TabPage(Tabs, "Two");
        TabThree = new TabPage(Tabs, "Three");
        Tabs.SelectedIndexChanged += this.OnTabChanged;

        Book = new Notebook(this);
        Book.SetBounds(320, 8, 300, 40);
        PageOne = new NotebookPage(Book, "One");
        PageTwo = new NotebookPage(Book, "Two");
        PageThree = new NotebookPage(Book, "Three");
        PageFour = new NotebookPage(Book, "Four");
        AddCaption(PageOne, "The first page");
        AddCaption(PageTwo, "The second page");
        AddCaption(PageThree, "The third page");
        AddCaption(PageFour, "The fourth page");
        Book.SelectedIndexChanged += this.OnPageChanged;

        Notes = new TextBox(this, true);
        Notes.SetBounds(320, 56, 300, 62);

        Choice = new RadioGroup(this);
        Choice.Text = "Choice";
        Choice.SetBounds(8, 126, 200, 110);
        Choice.Add("Low");
        Choice.Add("Normal");
        Choice.Add("High");
        Choice.SelectedIndexChanged += this.OnChoiceChanged;

        Loose = new SpeedButton(this);
        Loose.Text = "Loose";
        Loose.SetBounds(216, 132, 60, 24);
        Pen = new SpeedButton(this);
        Pen.Text = "Pen";
        Pen.SetBounds(216, 160, 60, 24);
        Pen.GroupIndex = 1;
        Brush = new SpeedButton(this);
        Brush.Text = "Brush";
        Brush.SetBounds(280, 160, 60, 24);
        Brush.GroupIndex = 1;

        Accept = new Button(this);
        Accept.Text = "OK";
        Accept.SetBounds(216, 200, 60, 26);
        Refuse = new Button(this);
        Refuse.Text = "Cancel";
        Refuse.SetBounds(280, 200, 60, 26);

        Slider = new TrackBar(this);
        Slider.SetBounds(352, 126, 268, 36);
        Gauge = new ProgressBar(this);
        Gauge.SetBounds(352, 166, 268, 20);
        Count = new SpinEdit(this);
        Count.SetBounds(352, 194, 80, 26);
        Scroller = new ScrollBar(this, false);
        Scroller.SetBounds(440, 196, 180, 20);

        // A splitter between a visible and a hidden neighbour, both docked to
        // its edge; only the visible one is what it resizes.
        Split = new Panel(this);
        Split.SetBounds(8, 244, 400, 120);
        Side = new Panel(Split);
        Side.Dock = DockStyle.Left;
        Side.Width = 100;
        Side.BackColor = Colors.Silver;
        Hidden = new Panel(Split);
        Hidden.Dock = DockStyle.Left;
        Hidden.Width = 60;
        Hidden.Visible = false;
        Divide = new Splitter(Split);
        Divide.Dock = DockStyle.Left;
        Rest = new Panel(Split);
        Rest.Dock = DockStyle.Fill;
        Rest.BackColor = Colors.White;

        Icons = new ImageList(16, 16);
        Tree = new TreeView(this);
        Tree.SetBounds(416, 244, 204, 120);
        Tree.Images = Icons;
        Tree.Add("Root").Add("Leaf");

        // Three bands sharing one row, and a fourth hidden before it is given
        // its control.
        Strip = new Panel(this);
        Strip.SetBounds(8, 372, 612, 80);
        Cool = new CoolBar(Strip);
        First = new CoolBand(Cool);
        First.Text = "First";
        Second = new CoolBand(Cool);
        Second.Text = "Second";
        Second.Break = false;
        Third = new CoolBand(Cool);
        Third.Text = "Third";
        Third.Break = false;
        Folded = new CoolBand(Cool);
        Folded.Visible = false;
        FoldedLabel = new Label(Cool);
        FoldedLabel.Text = "Folded away";
        Folded.Control = FoldedLabel;
        Cool.Change += this.OnCoolChanged;
    }

    void AddCaption(NotebookPage page, String text)
    {
        var said = new Label(page);
        said.SetBounds(8, 8, 260, 20);
        said.Text = text;
    }

    void BuildMenu()
    {
        Bar = new MainMenu();
        Bar.Renderer = new OfficeXpRenderer();
        var file = Bar.Add("&File");
        Shared = file.Add("&New");
        file.Add(MenuItem.Separator());
        file.Add("E&xit").Click += this.OnExit;
        Menu = Bar;

        Popup = new BuiltPopup();
        Popup.Add(Shared);
    }

    void OnExit(MenuItem sender) => Close();
    void OnTabChanged(Control sender) => TabChanges++;
    void OnPageChanged(Control sender) => PageChanges++;
    void OnChoiceChanged(Control sender) => ChoiceChanges++;
    void OnCoolChanged(Control sender) => CoolChanges++;

    void Settle()
    {
        for (int i = 0; i < 6; i++)
            Application.DoEvents();
    }

    // ------------------------------------------------------------ self test

    public bool SelfTest()
    {
        bool ok = true;

        // A text box compares against what it shows, which the user or
        // `Lines` may have changed since the program last set it.
        Notes.Text = "first";
        Notes.Lines = ["second"];
        Notes.Text = "first";
        ok = Check(ok, "a text box takes back a value it was given before",
                   Notes.Text == "first");

        // A page removed in front of the one showing leaves it showing.
        Book.SelectedIndex = 2;
        PageChanges = 0;
        Book.RemovePage(PageOne);
        ok = Check(ok, "a notebook keeps its page when one before it goes",
                   Book.SelectedPage == PageThree && Book.SelectedIndex == 1
                   && PageThree.Visible && !PageFour.Visible);
        ok = Check(ok, "and reports no change of page", PageChanges == 0);
        Book.RemovePage(PageThree);
        ok = Check(ok, "removing the page showing does report one",
                   PageChanges == 1 && Book.SelectedPage == PageFour);

        Tabs.SelectedIndex = 2;
        Settle();
        TabChanges = 0;
        Tabs.RemovePage(TabOne);
        Settle();
        ok = Check(ok, "a tab control keeps its page when one before it goes",
                   Tabs.SelectedPage == TabThree && TabThree.Visible);
        ok = Check(ok, "and reports no change of page", TabChanges == 0);

        // An index naming no page leaves the page and the tab as they were.
        Tabs.SelectedIndex = 7;
        Settle();
        ok = Check(ok, "a tab index past the end is ignored",
                   Tabs.SelectedIndex == 1 && TabThree.Visible && !TabTwo.Visible);

#if WINDOWS
        TabTwo.Text = "Renamed";
        ok = Check(ok, "a page's text is what its tab says",
                   TabCaption(Tabs, 0) == "Renamed");
#endif

        // A radio group can have nothing chosen, and says so once per choice.
        Choice.SelectedIndex = 1;
        Choice.SelectedIndex = -1;
        ok = Check(ok, "a radio group can have nothing chosen",
                   Choice.SelectedIndex == -1 && !Choice.Buttons[1u].Checked);
        ok = Check(ok, "and neither raised a change", ChoiceChanges == 0);

        // What Win32 reports for a click on the choice already ticked.
        Choice.SelectedIndex = 1;
        Choice.Buttons[1u].OnPlatformActivated();
        Choice.Buttons[1u].OnPlatformValueChanged();
        ok = Check(ok, "a click on the ticked choice is no change",
                   ChoiceChanges == 0);

        // What GTK reports for one click: both ticks move, and both say so.
        Choice.Buttons[2u].Checked = true;
        Choice.Buttons[1u].OnPlatformValueChanged();
        Choice.Buttons[1u].OnPlatformActivated();
        Choice.Buttons[2u].OnPlatformValueChanged();
        Choice.Buttons[2u].OnPlatformActivated();
        ok = Check(ok, "one choice is one change", ChoiceChanges == 1);

        // A speed button with no group never stays down, and the down button
        // of a group that must have one is raised only by pressing another.
        Loose.Down = true;
        ok = Check(ok, "an ungrouped speed button does not stay down", !Loose.Down);
        Pen.Down = true;
        Pen.Down = false;
        ok = Check(ok, "a group's only down button stays down", Pen.Down);
        Brush.Down = true;
        ok = Check(ok, "until another is pressed", Brush.Down && !Pen.Down);

        Accept.IsDefault = true;
        Refuse.IsDefault = true;
        ok = Check(ok, "one default button per form",
                   Refuse.IsDefault && !Accept.IsDefault);
#if WINDOWS
        ok = Check(ok, "and Windows agrees",
                   !IsDefaultButton(Accept) && IsDefaultButton(Refuse));
#endif

        // A range is never empty, and a value is kept inside it.
        Slider.Maximum = 10;
        Slider.Minimum = 20;
        ok = Check(ok, "a slider's minimum raises its maximum",
                   Slider.Maximum == 20 && Slider.Value == 20);
        Gauge.Minimum = 50;
        Gauge.Maximum = 30;
        ok = Check(ok, "a gauge's maximum lowers its minimum",
                   Gauge.Minimum == 30 && Gauge.Value == 30);
        Count.Minimum = 5;
        Count.Maximum = 1;
        Count.Value = 9;
        ok = Check(ok, "a spin edit keeps its range and value",
                   Count.Minimum == 1 && Count.Value == 1);
        Scroller.Maximum = 50;
        Scroller.Minimum = 80;
        ok = Check(ok, "a scroll bar keeps its range",
                   Scroller.Maximum == 80 && Scroller.Minimum == 80);

        // The splitter resizes the visible neighbour, never past the parent.
        DragSplitter(1000);
        ok = Check(ok, "a splitter resizes its visible neighbour",
                   Side.Width > 100 && Hidden.Width == 60);
        // With nothing between them, a drag of the whole screen stops where
        // the splitter reaches the far side of its parent.
        Hidden.Dock = DockStyle.None;
        DragSplitter(1000);
        ok = Check(ok, "and not past its parent",
                   Divide.Width == 5
                   && Divide.Left + Divide.Width <= Split.ClientBounds.Width);
        // The pointer leaves and comes back, which is when the platform asks.
        Divide.Dock = DockStyle.Top;
        Split.OnPlatformMouseLeave();
        Split.OnPlatformMouseMove(Forms.Drawing.Point.At(Divide.Left + 2, Divide.Top + 2),
                                  ModifierKeys.None);
        ok = Check(ok, "a top splitter sizes north to south",
                   Divide.Cursor == CursorKind.SizeNorthSouth);

#if WINDOWS
        Tree.Images = null;
        ok = Check(ok, "a tree can lose its pictures", TreeImageList(Tree) == 0u);
#endif

        // A press on the first band's handle that goes nowhere moves nothing.
        var handle = Forms.Drawing.Point.At(First.Left + 4, First.Top + First.Height / 2);
        Cool.OnPlatformMouseDown(MouseButton.Left, handle, ModifierKeys.None);
        Cool.OnPlatformMouseUp(MouseButton.Left, handle, ModifierKeys.None);
        ok = Check(ok, "a click on a band's handle keeps its row",
                   !Second.Break && !Third.Break && Second.Top == First.Top);
        ok = Check(ok, "and reports no change", CoolChanges == 0);
        ok = Check(ok, "a hidden band hides the control it is given",
                   !FoldedLabel.Visible);

        // A menu item in a menu bar and a popup belongs to both.
        nuint onBar = Shared.PlatformId;
        Popup.BuildAndDiscard();
        ok = Check(ok, "building a popup leaves the bar's item alone",
                   Shared.PlatformId == onBar);
        Shared.Enabled = false;
#if WINDOWS
        ok = Check(ok, "and a change still reaches the bar",
                   (MenuState(FileMenu(), 0u) & MfsGrayed) != 0u);
#endif
        Shared.Enabled = true;

        // A separator is an item under a renderer and the platform's own line
        // under the platform, so changing renderer changes what it is -- both
        // ways, and from a bar built under either. Each change builds the bar
        // again, and the one it replaces has to go quietly.
        Bar.Renderer = new SystemChromeRenderer();
        Settle();
#if WINDOWS
        ok = Check(ok, "a drawn separator becomes the platform's own",
                   (MenuType(FileMenu(), 1u) & MftSeparator) != 0u);
#endif
        Menu = Bar;
        Bar.Renderer = new OfficeXpRenderer();
        Settle();
#if WINDOWS
        uint type = MenuType(FileMenu(), 1u);
        ok = Check(ok, "and the platform's own becomes drawn",
                   (type & MftOwnerDraw) != 0u && (type & MftSeparator) == 0u);
#endif
        ok = Check(ok, "a rebuilt bar still has its items",
                   Shared.PlatformId != 0u);

        return ok;
    }

    /// Presses the splitter, moves the pointer `by` pixels along its axis and
    /// lets go, through its parent as the platform would.
    void DragSplitter(int by)
    {
        var from = Forms.Drawing.Point.At(Divide.Left + 2, Divide.Top + 10);
        var to = Forms.Drawing.Point.At(from.X + by, from.Y);
        Split.OnPlatformMouseMove(from, ModifierKeys.None);
        Split.OnPlatformMouseDown(MouseButton.Left, from, ModifierKeys.None);
        Split.OnPlatformMouseMove(to, ModifierKeys.None);
        Split.OnPlatformMouseUp(MouseButton.Left, to, ModifierKeys.None);
    }

#if WINDOWS
    HMENU FileMenu()
    {
        HMENU bar = GetMenu((HWND)(void*)Handle);
        var info = MenuAsking(MiimSubMenu);
        GetMenuItemInfoW(bar, 0u, 1, &info);
        return info.SubMenu;
    }
#endif

    bool Check(bool running, String what, bool passed)
    {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        return running && passed;
    }
}

#if WINDOWS
const uint TcmGetItemW = 0x133Cu;
const uint TvmGetImageList = 0x1108u;


/// A `MENUITEMINFO` asking for `mask`, with everything else zero.
MenuItemInfo MenuAsking(uint mask)
{
    MenuItemInfo info;
    info.Size = (uint)sizeof(MenuItemInfo);
    info.Mask = mask;
    info.Type = 0u;
    info.State = 0u;
    info.Id = 0u;
    info.SubMenu = null;
    info.Checked = null;
    info.Unchecked = null;
    info.ItemData = 0u;
    info.TypeData = null;
    info.TypeDataLength = 0u;
    info.Item = null;
    return info;
}

uint MenuType(HMENU menu, uint position)
{
    var info = MenuAsking(MiimFType);
    GetMenuItemInfoW(menu, position, 1, &info);
    return info.Type;
}

uint MenuState(HMENU menu, uint position)
{
    var info = MenuAsking(MiimState);
    GetMenuItemInfoW(menu, position, 1, &info);
    return info.State;
}

String TabCaption(TabControl tabs, int index)
{
    var buffer = new char16[64u];
    TabItem item;
    item.Mask = TcifText;
    item.State = 0u;
    item.StateMask = 0u;
    item.Text = &buffer[0u];
    item.TextLength = 64;
    item.Image = 0;
    item.Param = 0u;
    SendMessageW((HWND)(void*)tabs.Handle, TcmGetItemW, (ulong)index, (long)(nuint)&item);
    return Text.FromNullTerminatedUtf16(&buffer[0u]);
}

nuint TreeImageList(TreeView tree) =>
    (nuint)SendMessageW((HWND)(void*)tree.Handle, TvmGetImageList, 0u, 0);

bool IsDefaultButton(Button button)
{
    long style = GetWindowLongPtrW((HWND)(void*)button.Handle, GwlStyle);
    return (style & 15L) == (long)BsDefPushButton;
}
#endif

int Main()
{
    Application.Initialize();
    var form = new ChecksForm();

    bool testing = false;
    var arguments = Standard.Env.GetArguments();
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        if (arguments[i] == "--selftest")
            testing = true;
    }

    if (testing)
    {
        Console.WriteLine("Forms for Stainless -- control checks");
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
