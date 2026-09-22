// SPDX-License-Identifier: 0BSD
//
// What a platform reports, and what it holds.
//
//   stainless run samples/forms/backend.sl forms/src bindings/win32 \
//       -l user32 -l gdi32 -l comctl32 -l comdlg32 -l ole32 -l shell32 -l advapi32
//
// A handful of controls, and a `--selftest` that is the reason the program
// exists. Some checks are promises the seam makes on every platform: a change
// the program made is never reported as the user's, and a list selects one
// row. The rest are read back from the windows the Win32 backend made, which
// is the only place a fault in the backend shows -- the control layer's own
// fields say whatever they were told.
module BackendSample;

import Standard.Console;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if WINDOWS
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Gdi32;
import Win32.ComCtl32;
import Forms.Platform.Win32;
#endif

// `Point` means one thing to Forms and another to Win32.
using FPoint = Forms.Drawing.Point;

public class BackendForm : Form
{
    public TextBox Entry;
    public ListView Rows;
    public TreeView Tree;
    public TreeNode Second;
    public CheckListBox Chores;
    public SpinEdit Quantity;
    public HeaderControl Headings;
    public ScrollBar Bar;
    public Label Centred;
    public Label Righted;
    public ComboBox Choice;
    public MenuItem FileItem;

    public int UserEdits;
    public int TextChanges;
    public int RowChanges;
    public int NodeChanges;
    public int ChoreChanges;
    public int QuantityChanges;
    public int SectionChanges;
    public int BarChanges;

    public BackendForm()
    {
        base(WindowBorder.Sizable);
        Text = "Backend";
        SetBounds(0, 0, 660, 440);

        Entry = new TextBox(this);
        Entry.SetBounds(12, 12, 200, 24);
        Entry.UserTextChanged += this.OnUserEdit;
        Entry.TextChanged += this.OnTextChange;

        Rows = new ListView(this);
        Rows.SetBounds(12, 48, 200, 120);
        Rows.AddColumn("Item", 180);
        Rows.AddRow("Apples");
        Rows.AddRow("Screws");
        Rows.AddRow("Notebook");
        Rows.SelectedIndexChanged += this.OnRowChange;

        Tree = new TreeView(this);
        Tree.SetBounds(224, 12, 200, 156);
        var root = Tree.Add("Shopping");
        root.Add("Grocery");
        Second = root.Add("Hardware");
        root.Expand();
        Tree.SelectedNodeChanged += this.OnNodeChange;

        Chores = new CheckListBox(this);
        Chores.SetBounds(436, 12, 200, 110);
        Chores.SelectedIndexChanged += this.OnChoreChange;
        Chores.Add("Buy milk");
        Chores.Add("Post letter");
        Chores.Add("Fix shelf");

        Quantity = new SpinEdit(this);
        Quantity.SetBounds(436, 136, 80, 26);
        Quantity.ValueChanged += this.OnQuantityChange;

        Headings = new HeaderControl(this);
        Headings.SetBounds(12, 180, 300, 24);
        Headings.Add("Name", 120);
        Headings.Add("Size", 80);
        Headings.SectionResized += this.OnSectionChange;

        Bar = new ScrollBar(this, true);
        Bar.SetBounds(620, 180, 18, 200);
        Bar.Maximum = 100;
        Bar.PageSize = 25;
        Bar.ValueChanged += this.OnBarChange;

        // Aligned and not wrapping: the combination with no kind of its own.
        Centred = new Label(this);
        Centred.SetBounds(12, 216, 300, 20);
        Centred.Text = "Centred, and cut short with an ellipsis: far too long for its label";
        Centred.TextAlign = HorizontalAlignment.Center;
        Centred.WordWrap = false;

        Righted = new Label(this);
        Righted.SetBounds(12, 240, 300, 20);
        Righted.Text = "Right-aligned";
        Righted.TextAlign = HorizontalAlignment.Right;
        Righted.WordWrap = false;

        Choice = new ComboBox(this);
        Choice.SetBounds(324, 180, 180, 24);
        Choice.Add("One");
        Choice.Add("Two");
        Choice.Add("Three");
        Choice.Add("Four");
        Choice.SelectedIndex = 0;

        var menuBar = new MainMenu();
        FileItem = menuBar.Add("&File");
        FileItem.Add("E&xit").Click += this.OnExit;
        Menu = menuBar;
    }

    void OnUserEdit(Control sender) => UserEdits++;
    void OnTextChange(Control sender) => TextChanges++;
    void OnRowChange(Control sender) => RowChanges++;
    void OnNodeChange(Control sender) => NodeChanges++;
    void OnChoreChange(Control sender) => ChoreChanges++;
    void OnQuantityChange(Control sender) => QuantityChanges++;
    void OnSectionChange(Control sender) => SectionChanges++;
    void OnBarChange(Control sender) => BarChanges++;
    void OnExit(MenuItem sender) => Close();

    // ------------------------------------------------------------ self test

    public bool SelfTest()
    {
        bool ok = true;
        ok = CheckQuietChanges(ok);
        ok = CheckSingleSelection(ok);
#if WINDOWS
        ok = CheckUserChanges(ok);
        ok = CheckNativeState(ok);
        ok = CheckOwnership(ok);
        ok = CheckDrawing(ok);
#endif
        return ok;
    }

    /// A change the program makes is not the user's, so it raises no event
    /// that is only for the user's -- which is what stops a two-way binding
    /// answering its own write.
    bool CheckQuietChanges(bool ok)
    {
        ok = Check(ok, "nothing reported while the form was built",
                   UserEdits == 0 && RowChanges == 0 && NodeChanges == 0
                   && ChoreChanges == 0 && QuantityChanges == 0 && SectionChanges == 0);

        Entry.Text = "set by the program";
        Pump();
        ok = Check(ok, "setting a text box's text is not a user edit", UserEdits == 0);
        ok = Check(ok, "and changes its text once", TextChanges == 1);

        Rows.SelectedIndex = 1;
        Pump();
        ok = Check(ok, "selecting a row is not reported", RowChanges == 0);

        Tree.SelectedNode = Second;
        Pump();
        ok = Check(ok, "selecting a node is not reported", NodeChanges == 0);

        Chores.SetChecked(1, true);
        Chores.Add("Water plants");
        Pump();
        ok = Check(ok, "ticking or adding a chore is not reported", ChoreChanges == 0);
        ok = Check(ok, "and the tick is there", Chores.IsChecked(1));

        Quantity.Value = 7;
        Pump();
        ok = Check(ok, "setting a spin edit's value is not reported", QuantityChanges == 0);
        ok = Check(ok, "and the value is there", Quantity.Value == 7);

        Headings.SetSectionWidth(0, 150);
        Pump();
        ok = Check(ok, "setting a heading's width is not reported", SectionChanges == 0);
        ok = Check(ok, "and the width is there", Headings.SectionWidth(0) == 150);
        return ok;
    }

    bool CheckSingleSelection(bool ok)
    {
        Rows.SelectedIndex = 0;
        Rows.SelectedIndex = 2;
        ok = Check(ok, "a list moves its selection rather than adding to it",
                   Rows.SelectedIndex == 2);
        Rows.SelectedIndex = -1;
        ok = Check(ok, "and -1 clears it", Rows.SelectedIndex == -1);

        Chores.SelectedIndex = 0;
        Chores.SelectedIndex = 2;
        ok = Check(ok, "a check list moves its selection too", Chores.SelectedIndex == 2);
        Chores.SelectedIndex = -1;
        ok = Check(ok, "and clears it", Chores.SelectedIndex == -1);
        return ok;
    }

#if WINDOWS
    /// The same changes made behind the peer's back, as the user makes them:
    /// each is reported exactly once.
    bool CheckUserChanges(bool ok)
    {
        int edits = UserEdits;
        SetWindowTextW(WindowOf(Entry), "typed".ToUtf16().ToPointer());
        Pump();
        ok = Check(ok, "an edit the program did not make is reported", UserEdits == edits + 1);

        HWND rows = WindowOf(Rows);
        int moved = RowChanges;
        var chosen = ListItemState(LvisSelected, LvisSelected);
        SendMessageW(rows, LvmSetItemState, 1u, (nint)(void*)&chosen);
        Pump();
        ok = Check(ok, "a row the user selects is reported once", RowChanges == moved + 1);

        var focused = ListItemState(LvisFocused, LvisFocused);
        SendMessageW(rows, LvmSetItemState, 1u, (nint)(void*)&focused);
        Pump();
        ok = Check(ok, "the focus arriving on it is not", RowChanges == moved + 1);

        ok = Check(ok, "one row is selected, not two",
                   SendMessageW(rows, LvmGetSelectedCount, 0u, 0) == 1);

        var cleared = ListItemState(0u, LvisSelected);
        SendMessageW(rows, LvmSetItemState, (nuint)(nint)(-1), (nint)(void*)&cleared);
        Pump();
        ok = Check(ok, "the selection emptying is reported too", RowChanges == moved + 2);

        int ticked = ChoreChanges;
        var tick = ListItemState(GetCheckedStateMask(true), LvisStateImageMask);
        SendMessageW(WindowOf(Chores), LvmSetItemState, 2u, (nint)(void*)&tick);
        Pump();
        ok = Check(ok, "a tick the user makes is reported", ChoreChanges == ticked + 1);

        int counted = QuantityChanges;
        SendMessageW(ArrowsOf(WindowOf(Quantity)), UdmSetPos32, 0u, 9);
        Pump();
        ok = Check(ok, "the arrows moving the value are reported",
                   QuantityChanges == counted + 1);
        return ok;
    }

    /// What the windows hold, rather than what the controls were told.
    bool CheckNativeState(bool ok)
    {
        long centredStyle = GetWindowLongPtrW(WindowOf(Centred), GwlStyle);
        ok = Check(ok, "a centred label that does not wrap is still a text label",
                   ((uint)centredStyle & SsTypeMask) == SsCenter);
        long rightStyle = GetWindowLongPtrW(WindowOf(Righted), GwlStyle);
        ok = Check(ok, "and so is a right-aligned one",
                   ((uint)rightStyle & SsTypeMask) == SsRight);

        HWND combo = WindowOf(Choice);
        Win32.User32.Rect closed;
        GetWindowRect(combo, &closed);
        Win32.User32.Rect dropped;
        SendMessageW(combo, CbGetDroppedControlRect, 0u, (nint)(void*)&dropped);
        int row = (int)SendMessageW(combo, CbGetItemHeight, 0u, 0);
        ok = Check(ok, "a combo box's list has room for its items",
                   (dropped.Bottom - dropped.Top) - (closed.Bottom - closed.Top) >= 4 * row);

        Win32.User32.Rect frame;
        GetWindowRect(WindowOf(this), &frame);
        ok = Check(ok, "a form with a menu bar knows its whole height",
                   Height == frame.Bottom - frame.Top);

        HWND header = (HWND)(void*)(nuint)SendMessageW(WindowOf(Chores), LvmGetHeader, 0u, 0);
        Win32.User32.Rect heading;
        heading.Top = 0;
        heading.Bottom = 0;
        if (header != null)
            GetWindowRect(header, &heading);
        // A list view keeps its header window and sizes it to nothing.
        ok = Check(ok, "a check list shows no empty column heading",
                   heading.Bottom - heading.Top == 0);

        Quantity.Enabled = false;
        ok = Check(ok, "a disabled spin edit's arrows are disabled",
                   IsWindowEnabled(ArrowsOf(WindowOf(Quantity))) == 0);
        Quantity.Enabled = true;

        // A page is the page size, and the ends are the ends.
        HWND scroller = WindowOf(Bar);
        Bar.Value = 0;
        int barred = BarChanges;
        SendMessageW(WindowOf(this), WmVerticalScroll, SbPageDown, (nint)(void*)scroller);
        ok = Check(ok, "a page down moves by the page size", Bar.Value == 25);
        SendMessageW(WindowOf(this), WmVerticalScroll, SbBottom, (nint)(void*)scroller);
        ok = Check(ok, "the end goes to the last page", Bar.Value == 100 - 25 + 1);
        SendMessageW(WindowOf(this), WmVerticalScroll, SbTop, (nint)(void*)scroller);
        ok = Check(ok, "and the start to the first", Bar.Value == 0);
        ok = Check(ok, "each of them is reported", BarChanges == barred + 3);

        // Far more items than sixteen bits can number, as a context menu
        // rebuilt on every showing adds up to.
        bool fits = true;
        var owner = new MenuItem("x");
        for (int i = 0; i < 40000; i++)
        {
            var menu = WidgetSet.Current.CreateMenu();
            var item = menu.AddItem(owner, "x", null);
            if (item.Id > 0xFFFFu)
                fits = false;
        }
        ok = Check(ok, "menu ids stay within what WM_COMMAND carries", fits);

        // Replacing only the bits of the frame, and not the visibility.
        var ghost = new Form(WindowBorder.Sizable);
        var peer = ghost.WindowPeer();
        peer.SetVisible(true);
        peer.SetBorder(WindowBorder.Fixed);
        ok = Check(ok, "changing a border leaves a window visible",
                   IsWindowVisible((HWND)(void*)peer.Handle) != 0);
        peer.SetVisible(false);
        return ok;
    }

    /// Handles that belong to one object and are shared with another.
    bool CheckOwnership(bool ok)
    {
        var ghost = new Form(WindowBorder.Sizable);

        // A brush made for a control whose window went first is still freed.
        HANDLE self = GetCurrentProcess();
        uint before = GetGuiResources(self, GrGdiObjects);
        for (int i = 0; i < 40; i++)
            LoseColouredPanel(ghost);
        uint after = GetGuiResources(self, GrGdiObjects);
        ok = Check(ok, "a control that outlives its window frees its brush",
                   after < before + 10u);

        // An image list a list view was given is the image list's to destroy.
        var icons = new ImageList(16, 16);
        var pixels = new byte[16u * 16u * 4u];
        for (nuint i = 0u; i < pixels.Length; i++)
            pixels[i] = (byte)200;
        var picture = Bitmap.FromPixels(16, 16, pixels);
        if (picture.Ok)
            icons.Add(picture.Value);
        HIMAGELIST shared = (HIMAGELIST)(void*)icons.Backend().Handle;
        LoseListViewWith(ghost, icons);
        ok = Check(ok, "a list view leaves the image list it shared",
                   ImageList_GetImageCount(shared) == 1);

        // A submenu let go of by the menu it was under is still a menu.
        var outer = WidgetSet.Current.CreateMenu();
        var inner = WidgetSet.Current.CreateMenu();
        inner.AddItem(new MenuItem("in"), "in", null);
        outer.AddItem(new MenuItem("sub"), "sub", inner);
        outer.Clear();
        ok = Check(ok, "clearing a menu leaves its submenus to their owners",
                   IsMenu((HMENU)(void*)inner.Handle) != 0);

        // A menu bar a window is made to let go of is destroyed with its peer.
        nuint replaced = ReplaceMenuBar(ghost.WindowPeer());
        ok = Check(ok, "a replaced menu bar is destroyed",
                   IsMenu((HMENU)(void*)replaced) == 0);
        return ok;
    }

    /// Drawing into a bitmap of our own, and reading the pixels back.
    bool CheckDrawing(bool ok)
    {
        var font = new Font("Segoe UI", 12);
        var canvas = new Canvas(120, 30);
        var surface = new GraphicsBackend(canvas.Dc, Forms.Drawing.Rectangle.FromBounds(0, 0, 120, 30));
        surface.DrawString("A&&B&C", font, Colors.Black, 0, 0);
        var literal = canvas.Pixels();

        canvas.Clear();
        surface.DrawStringIn("A&&B&C", font, Colors.Black,
                             Forms.Drawing.Rectangle.FromBounds(0, 0, 120, 30), TextFormat.Default);
        var laidOut = canvas.Pixels();
        ok = Check(ok, "text in a rectangle draws an ampersand as itself",
                   SamePixels(literal, laidOut));

        canvas.Clear();
        FPoint[] triangle = [Forms.Drawing.Point.FromXY(10, 5), Forms.Drawing.Point.FromXY(100, 5),
                              Forms.Drawing.Point.FromXY(55, 25)];
        surface.FillPolygon(new Brush(Colors.Red), triangle);
        var filled = canvas.Pixels();
        ok = Check(ok, "a filled polygon is not outlined in black",
                   AnyPixelIs(filled, 255u, 0u, 0u) && !AnyPixelIs(filled, 0u, 0u, 0u));

        HPEN mine = CreatePen(PenSolid, 3, 0x00FF0000u);
        HGDIOBJ was = SelectObject(canvas.Dc, (HGDIOBJ)(void*)mine);
        surface.DrawLine(new Pen(Colors.Green), 0, 0, 50, 20);
        ok = Check(ok, "drawing a line puts back the pen that was selected",
                   GetCurrentObject(canvas.Dc, ObjPen) == (HGDIOBJ)(void*)mine);
        SelectObject(canvas.Dc, was);
        DeleteObject((HGDIOBJ)(void*)mine);
        return ok;
    }

    /// The window behind a control.
    HWND WindowOf(WindowedControl control) => (HWND)(void*)control.Handle;
#endif

    void Pump()
    {
        for (int i = 0; i < 6; i++)
            Application.DoEvents();
    }

    bool Check(bool running, String what, bool passed)
    {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        return running && passed;
    }
}

#if WINDOWS
/// An `LVITEMW` that sets the state bits in `mask` to `state`.
ListItem ListItemState(uint state, uint mask)
{
    ListItem item;
    item.Mask = LvifState;
    item.Item = 0;
    item.SubItem = 0;
    item.State = state;
    item.StateMask = mask;
    item.Text = null;
    item.TextLength = 0;
    item.Image = 0;
    item.Param = 0u;
    item.Indent = 0;
    item.GroupId = 0;
    item.Columns = 0u;
    item.ColumnFormat = null;
    return item;
}

/// The up-down a spin edit's edit is the buddy of: a sibling, not a child.
HWND ArrowsOf(HWND edit)
{
    HWND child = GetWindow(GetParent(edit), GwChild);
    while (child != null)
    {
        if ((HWND)(void*)(nuint)SendMessageW(child, UdmGetBuddy, 0u, 0) == edit
            && ClassNameOf(child) == "msctls_updown32")
        {
            return child;
        }
        child = GetWindow(child, GwHwndNext);
    }
    return null;
}

String ClassNameOf(HWND window)
{
    var buffer = new char16[64u];
    int units = GetClassNameW(window, &buffer[0u], 64);
    if (units <= 0)
        return "";
    return Text.FromUtf16(&buffer[0u], (nuint)units);
}

/// A coloured panel whose window is destroyed under it, and then the panel.
void LoseColouredPanel(Form host)
{
    var panel = WidgetSet.Current.CreatePanel(host, host.WindowPeer());
    panel.SetBackColor(Colors.Red);
    DestroyWindow((HWND)(void*)panel.Handle);
}

/// A list view given `icons`, whose window is destroyed under it.
void LoseListViewWith(Form host, ImageList icons)
{
    var list = WidgetSet.Current.CreateListView(host, host.WindowPeer());
    list.SetImages(icons.Backend());
    DestroyWindow((HWND)(void*)list.Handle);
}

/// Gives a window one menu bar and then another, and answers the first one's
/// handle once nothing holds it.
nuint ReplaceMenuBar(IWindowPeer window)
{
    var first = WidgetSet.Current.CreateMenuBar();
    first.AddItem(new MenuItem("one"), "one", null);
    window.SetMenu(first);
    nuint handle = first.Handle;
    ReplaceWithSecondBar(window);
    return handle;
}

void ReplaceWithSecondBar(IWindowPeer window)
{
    var second = WidgetSet.Current.CreateMenuBar();
    second.AddItem(new MenuItem("two"), "two", null);
    window.SetMenu(second);
}

bool SamePixels(byte[] left, byte[] right)
{
    if (left.Length != right.Length)
        return false;
    for (nuint i = 0u; i < left.Length; i++)
    {
        if (left[i] != right[i])
            return false;
    }
    return true;
}

/// Whether any pixel of a 32-bit DIB is exactly this colour.
bool AnyPixelIs(byte[] pixels, uint red, uint green, uint blue)
{
    for (nuint i = 0u; i + 3u < pixels.Length; i = i + 4u)
    {
        if ((uint)pixels[i] == blue && (uint)pixels[i + 1u] == green
            && (uint)pixels[i + 2u] == red)
        {
            return true;
        }
    }
    return false;
}

/// A white 32-bit bitmap selected into a memory device context.
public class Canvas
{
    HDC _dc;
    HBITMAP _sheet;
    HGDIOBJ _was;
    byte* _bits;
    int _width;
    int _height;

    public Canvas(int width, int height)
    {
        _width = width;
        _height = height;
        BitmapInfo info;
        info.Header.Size = (uint)sizeof(BitmapInfoHeader);
        info.Header.Width = width;
        info.Header.Height = -height;
        info.Header.Planes = (ushort)1;
        info.Header.BitCount = (ushort)32;
        info.Header.Compression = BitmapCompressionRgb;
        info.Header.ImageByteLength = 0u;
        info.Header.PixelsPerMeterX = 0;
        info.Header.PixelsPerMeterY = 0;
        info.Header.ColoursUsed = 0u;
        info.Header.ColoursImportant = 0u;
        info.FirstColour = 0u;

        void* bits = null;
        _sheet = CreateDIBSection(null, &info, DibRgbColours, &bits, null, 0u);
        _bits = (byte*)bits;
        _dc = CreateCompatibleDC(null);
        _was = SelectObject(_dc, (HGDIOBJ)(void*)_sheet);
        Clear();
    }

    ~Canvas()
    {
        SelectObject(_dc, _was);
        DeleteDC(_dc);
        DeleteObject((HGDIOBJ)(void*)_sheet);
    }

    public HDC Dc => _dc;

    public void Clear()
    {
        Win32.User32.Rect whole;
        whole.Left = 0;
        whole.Top = 0;
        whole.Right = _width;
        whole.Bottom = _height;
        FillRect(_dc, &whole, (HBRUSH)(void*)GetStockObject(WhiteBrush));
    }

    /// A copy of what has been drawn, once GDI has finished drawing it.
    public byte[] Pixels()
    {
        GdiFlush();
        nuint size = (nuint)_width * (nuint)_height * 4u;
        var copy = new byte[size];
        for (nuint i = 0u; i < size; i++)
            copy[i] = _bits[i];
        return copy;
    }
}
#endif

int Main()
{
    Application.Initialize();
    var form = new BackendForm();

    bool testing = false;
    var arguments = Standard.Env.GetArguments();
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        if (arguments[i] == "--selftest")
            testing = true;
    }

    if (testing)
    {
        Console.WriteLine("Forms for Stainless -- what the platform holds");
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
