// SPDX-License-Identifier: 0BSD
//
// What a platform reports to a control, and what it must not.
//
//   stainless run samples/forms/reports.sl forms/src bindings/win32 \
//       -l user32 -l gdi32 -l comctl32
//
// A control hears about the user's doing and nothing else: not a value the
// program set, not a click meant for a child, not a letter that was really a
// shortcut. Each of those is a report the platform raises on its own, so each
// backend has to hold it back, and this window is where that is checked.
//
// `--selftest` builds the window and runs the checks. The ones that need a
// user's hand drive the platform directly -- GTK's own calls, and simulated X
// input where the display can take it -- and say they were skipped elsewhere.
module Reports;

import Standard.Console;
import Standard.Text;
import Standard.Collections;
import Standard.Threading;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if UNIX
import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;
import Gtk.Cairo;
import Forms.Platform.Gtk;
#endif

public class ReportsForm : Form
{
    public CheckBox Option;
    public TextBox Entry;
    public ComboBox Combo;
    public ListBox Rows;
    public ScrollBar Scroll;
    public SpinEdit Spin;
    public TrackBar Track;
    public TabControl Tabs;
    public TabPage First;
    public TabPage Second;
    public Panel Pane;
    public PaintBox Box;
    public Panel Choices;
    public RadioButton Near;
    public RadioButton Far;
    public Button Back;
    public Button Front;
    public MenuItem Go;
    public MenuItem Ticked;

    // What each control reported, counted.
    public int Options;
    public int Edits;
    public int Combos;
    public int Lists;
    public int Scrolls;
    public int Spins;
    public int Tracks;
    public int TabChanges;
    public int NearChanges;
    public int FarChanges;
    public int Goes;
    public int Ticks;

    public int FormDowns;
    public Point FormAt;
    public int PaneDowns;
    public Point PaneAt;
    public int BoxDowns;
    public Point BoxAt;
    public int BackDowns;

    public int KeyDowns;
    public Key LastKey;
    public ModifierKeys LastModifiers;
    public int KeyPresses;
    public uint LastTyped;

    public ReportsForm()
    {
        base(WindowBorder.Sizable);
        Text = "Reports";
        SetBounds(0, 0, 640, 440);

        var bar = new MainMenu();
        var file = bar.Add("&File");
        Go = file.Add("&Go");
        Go.Click += this.OnGo;
        Ticked = file.Add("&Ticked");
        Ticked.Checked = true;
        Ticked.Click += this.OnTicked;
        Menu = bar;

        Option = new CheckBox(this);
        Option.Text = "Option";
        Option.SetBounds(8, 8, 120, 24);
        Option.CheckedChanged += this.OnOption;

        Entry = new TextBox(this);
        Entry.SetBounds(136, 8, 160, 26);
        Entry.UserTextChanged += this.OnEdit;
        Entry.KeyDown += this.OnEntryKeyDown;
        Entry.KeyPress += this.OnEntryKeyPress;

        Combo = new ComboBox(this);
        Combo.SetBounds(304, 8, 140, 28);
        Combo.Add("one");
        Combo.Add("two");
        Combo.Add("three");
        Combo.SelectedIndexChanged += this.OnCombo;

        Rows = new ListBox(this);
        Rows.SetBounds(8, 44, 140, 90);
        Rows.Add("one");
        Rows.Add("two");
        Rows.Add("three");
        Rows.SelectedIndexChanged += this.OnList;

        // Each of the three is told about a range change before anything else
        // has been set, so the guard is down when the platform clamps.
        Scroll = new ScrollBar(this, false);
        Scroll.SetBounds(156, 44, 200, 18);
        Scroll.ValueChanged += this.OnScroll;

        Spin = new SpinEdit(this);
        Spin.SetBounds(156, 70, 90, 28);
        Spin.ValueChanged += this.OnSpin;

        Track = new TrackBar(this);
        Track.SetBounds(156, 104, 200, 32);
        Track.ValueChanged += this.OnTrack;

        // Subscribed before any page exists, so that adding the first one is
        // heard if the platform reports it.
        Tabs = new TabControl(this);
        Tabs.SetBounds(452, 8, 180, 128);
        Tabs.SelectedIndexChanged += this.OnTab;
        First = new TabPage(Tabs, "First");
        Second = new TabPage(Tabs, "Second");

        Pane = new Panel(this);
        Pane.SetBounds(8, 200, 240, 150);
        Pane.MouseDown += this.OnPaneDown;

        Box = new PaintBox(Pane);
        Box.SetBounds(20, 20, 60, 40);
        Box.MouseDown += this.OnBoxDown;

        Choices = new Panel(this);
        Choices.SetBounds(260, 200, 160, 70);
        Near = new RadioButton(Choices);
        Near.Text = "Left";
        Near.SetBounds(4, 4, 140, 24);
        Near.CheckedChanged += this.OnNear;
        Far = new RadioButton(Choices);
        Far.Text = "Right";
        Far.SetBounds(4, 36, 140, 24);
        Far.CheckedChanged += this.OnFar;

        // Two buttons over one another, the second made last and so in front.
        Back = new Button(this);
        Back.Text = "Back";
        Back.SetBounds(440, 200, 100, 30);
        Back.MouseDown += this.OnBackDown;
        Front = new Button(this);
        Front.Text = "Front";
        Front.SetBounds(460, 210, 100, 30);

        MouseDown += this.OnFormDown;
    }

    void OnGo(MenuItem sender) => Goes++;
    void OnTicked(MenuItem sender) => Ticks++;
    void OnOption(Control sender) => Options++;
    void OnEdit(Control sender) => Edits++;
    void OnCombo(Control sender) => Combos++;
    void OnList(Control sender) => Lists++;
    void OnScroll(Control sender) => Scrolls++;
    void OnSpin(Control sender) => Spins++;
    void OnTrack(Control sender) => Tracks++;
    void OnTab(Control sender) => TabChanges++;
    void OnNear(Control sender) => NearChanges++;
    void OnFar(Control sender) => FarChanges++;
    void OnBackDown(Control sender, MouseEventArgs args) => BackDowns++;

    void OnFormDown(Control sender, MouseEventArgs args)
    {
        FormDowns++;
        FormAt = args.Location;
    }

    void OnPaneDown(Control sender, MouseEventArgs args)
    {
        PaneDowns++;
        PaneAt = args.Location;
    }

    void OnBoxDown(Control sender, MouseEventArgs args)
    {
        BoxDowns++;
        BoxAt = args.Location;
    }

    void OnEntryKeyDown(Control sender, KeyEventArgs args)
    {
        KeyDowns++;
        LastKey = args.Key;
        LastModifiers = args.Modifiers;
    }

    void OnEntryKeyPress(Control sender, KeyPressEventArgs args)
    {
        KeyPresses++;
        LastTyped = (uint)args.KeyChar;
    }
}

/// Runs the loop until whatever was just sent has arrived. Simulated input
/// goes out to the display and comes back, so pumping once is not enough.
void SettleEvents()
{
    for (int i = 0; i < 12; i++)
    {
        Standard.Threading.Sleep(5u);
        Application.DoEvents();
    }
}

bool ReportCheck(bool running, String what, bool passed)
{
    Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
    return running && passed;
}

void ReportSkipped(String what) => Console.WriteLine("  skip " + what);

String FormatPoint(Point at)
{
    return "(" + Standard.Text.FromInteger((long)at.X) + ", "
         + Standard.Text.FromInteger((long)at.Y) + ")";
}

// ============================================================ both platforms

/// What must hold whoever is driving: a value the program set, a range it
/// narrowed, a choice nobody has made.
bool CheckPortable(ReportsForm form)
{
    bool ok = true;

    ok = ReportCheck(ok, "adding the first tab reports no change of tab", form.TabChanges == 0);
    ok = ReportCheck(ok, "the first tab is the one showing",
                     form.Tabs.SelectedIndex == 0 && form.First.Visible && !form.Second.Visible);

    // A radio button starts unticked, as it does on Windows.
    ok = ReportCheck(ok, "no radio button starts ticked", !form.Near.Checked && !form.Far.Checked);
    ok = ReportCheck(ok, "and joining a group reports nothing",
                     form.NearChanges == 0 && form.FarChanges == 0);
    form.Far.Checked = true;
    ok = ReportCheck(ok, "a radio button can be ticked", form.Far.Checked && !form.Near.Checked);
    form.Far.Checked = false;
    ok = ReportCheck(ok, "and unticked by the program", !form.Far.Checked && !form.Near.Checked);
    ok = ReportCheck(ok, "and neither is reported", form.NearChanges == 0 && form.FarChanges == 0);

    // Narrowing a range moves a value that no longer fits, and that is the
    // program's doing too.
    form.Scroll.Minimum = 10;
    form.Spin.Minimum = 10;
    form.Track.Minimum = 10;
    SettleEvents();
    ok = ReportCheck(ok, "a scroll bar clamped by its range reports nothing", form.Scrolls == 0);
    ok = ReportCheck(ok, "nor does a spin edit", form.Spins == 0);
    ok = ReportCheck(ok, "nor does a track bar", form.Tracks == 0);

    // Windows stops a thumb a page short of the maximum, less one.
    form.Scroll.Minimum = 0;
    form.Scroll.Maximum = 100;
    form.Scroll.PageSize = 10;
    form.Scroll.Value = 100;
    ok = ReportCheck(ok, "a scroll bar stops a page short of its maximum",
                     form.Scroll.Value == 91);
    form.Scroll.Value = 0;
    ok = ReportCheck(ok, "and setting it reports nothing", form.Scrolls == 0);

    // Centred on the work area, after the form was placed somewhere else.
    var other = new Form(WindowBorder.Sizable);
    other.Text = "Centred";
    other.SetBounds(0, 0, 300, 200);
    var stretched = new TextBox(other);
    stretched.SetBounds(10, 10, 200, 26);
    stretched.Anchors = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
    other.CenterOnScreen();
    other.Show();
    SettleEvents();
    var area = Screen.WorkArea;
    int wantX = area.X + (area.Width - other.Width) / 2;
    int wantY = area.Y + (area.Height - other.Height) / 2;
    int awayX = other.Left - wantX;
    int awayY = other.Top - wantY;
    ok = ReportCheck(ok, "a form placed and then centred is centred, at "
                         + FormatPoint(Point.FromXY(other.Left, other.Top)) + " for "
                         + FormatPoint(Point.FromXY(wantX, wantY)),
                     awayX >= -1 && awayX <= 1 && awayY >= -1 && awayY <= 1);

    // Placed twice before it is shown, a window is configured at interim
    // sizes under a window manager, and none of them may reach the layout.
    ok = ReportCheck(ok, "and what it holds is laid out for the size it was given: "
                         + Standard.Text.FromInteger((long)stretched.Width),
                     other.Width == 300 && stretched.Width == 200);
    other.Close();
    SettleEvents();

    return ok;
}

// ================================================================ GTK only

#if UNIX

/// Every GLib warning and critical, counted and then printed as GLib would.
static class GlibWatch
{
    public static int Complaints = 0;
}

void CountComplaint(gchar* domain, gint level, gchar* message, gpointer data)
{
    if ((level & (G_LOG_LEVEL_CRITICAL | G_LOG_LEVEL_WARNING)) != 0)
        GlibWatch.Complaints++;
    g_log_default_handler(domain, level, message, data);
}

void WatchGlib() => g_log_set_default_handler(CountComplaint, null);

GtkWidget* WidgetOfControl(WindowedControl control) => (GtkWidget*)(void*)control.Handle;

/// Where a point in `control`'s own coordinates is in its form's window.
Point PointInForm(Form form, WindowedControl control, int x, int y)
{
    gint intoX = 0;
    gint intoY = 0;
    gtk_widget_translate_coordinates(WidgetOfControl(control), WidgetOfControl(form), x, y,
                                     &intoX, &intoY);
    return Point.FromXY(intoX, intoY);
}

/// A left click at a point in the form's window. False where the display
/// cannot simulate one, which Broadway cannot.
bool ClickFormAt(Form form, Point at)
{
    var window = (GdkWindow*)gtk_widget_get_window(WidgetOfControl(form));
    if (gdk_test_simulate_button(window, at.X, at.Y, 1u, 0u, GDK_BUTTON_PRESS) == 0)
        return false;
    gdk_test_simulate_button(window, at.X, at.Y, 1u, 0u, GDK_BUTTON_RELEASE);
    SettleEvents();
    return true;
}

bool PressKeyOn(Form form, guint keyval, guint modifiers)
{
    var window = (GdkWindow*)gtk_widget_get_window(WidgetOfControl(form));
    if (gdk_test_simulate_key(window, -1, -1, keyval, modifiers, GDK_KEY_PRESS) == 0)
        return false;
    gdk_test_simulate_key(window, -1, -1, keyval, modifiers, GDK_KEY_RELEASE);
    SettleEvents();
    return true;
}

/// The user changing each control's value after the program already has.
bool CheckUserChanges(ReportsForm form)
{
    bool ok = true;

    form.Option.Checked = true;
    gtk_button_clicked(WidgetOfControl(form.Option));
    ok = ReportCheck(ok, "a check box ticked by the program still reports the user",
                     form.Options == 1 && !form.Option.Checked);

    form.Entry.Text = "set";
    gtk_entry_set_text(WidgetOfControl(form.Entry), "typed".ToPointer());
    ok = ReportCheck(ok, "a text box reports typing after a program change", form.Edits == 1);

    form.Combo.SelectedIndex = 0;
    gtk_combo_box_set_active(WidgetOfControl(form.Combo), 1);
    ok = ReportCheck(ok, "a combo box reports a choice after a program change", form.Combos == 1);
    form.Combo.RemoveAt(1u);
    ok = ReportCheck(ok, "and removing the chosen item reports nothing", form.Combos == 1);

    form.Rows.SelectedIndex = 0;
    GtkWidget* view = gtk_bin_get_child(WidgetOfControl(form.Rows));
    GtkTreeIter row;
    gtk_tree_model_iter_nth_child(gtk_tree_view_get_model(view), &row, null, 2);
    gtk_tree_selection_select_iter(gtk_tree_view_get_selection(view), &row);
    ok = ReportCheck(ok, "a list reports a choice after a program change", form.Lists == 1);
    form.Rows.RemoveAt(2u);
    ok = ReportCheck(ok, "and removing the chosen row reports nothing", form.Lists == 1);

    form.Scroll.Value = 5;
    gtk_range_set_value(WidgetOfControl(form.Scroll), 20.0);
    ok = ReportCheck(ok, "a scroll bar reports a drag after a program change", form.Scrolls == 1);

    form.Spin.Value = 12;
    gtk_spin_button_set_value(WidgetOfControl(form.Spin), 30.0);
    ok = ReportCheck(ok, "a spin edit reports a click after a program change", form.Spins == 1);

    form.Track.Value = 12;
    gtk_range_set_value(WidgetOfControl(form.Track), 30.0);
    ok = ReportCheck(ok, "a track bar reports a drag after a program change", form.Tracks == 1);

    form.Tabs.SelectedIndex = 1;
    form.Tabs.SelectedIndex = 0;
    int before = form.TabChanges;
    gtk_notebook_set_current_page(WidgetOfControl(form.Tabs), 1);
    SettleEvents();
    ok = ReportCheck(ok, "a tab chosen by the user after the program chose one is reported, "
                         + Standard.Text.FromInteger((long)(form.TabChanges - before)) + " times",
                     form.TabChanges == before + 1);
    ok = ReportCheck(ok, "and shows its page", form.Second.Visible && !form.First.Visible);

    gtk_button_clicked(WidgetOfControl(form.Near));
    ok = ReportCheck(ok, "a radio button clicked is ticked and reported",
                     form.Near.Checked && form.NearChanges == 1);
    gtk_button_clicked(WidgetOfControl(form.Far));
    ok = ReportCheck(ok, "and the one it unticks reports nothing, as on Windows",
                     form.Far.Checked && !form.Near.Checked
                     && form.FarChanges == 1 && form.NearChanges == 1);

    return ok;
}

/// Choosing a menu command leaves its tick as the program set it.
bool CheckMenus(ReportsForm form)
{
    bool ok = true;
    var go = (GtkWidget*)(void*)form.Go.PlatformId;
    var ticked = (GtkWidget*)(void*)form.Ticked.PlatformId;

    gtk_menu_item_activate(go);
    ok = ReportCheck(ok, "choosing a command reports it", form.Goes == 1);
    ok = ReportCheck(ok, "and leaves no tick behind", gtk_check_menu_item_get_active(go) == 0);
    gtk_menu_item_activate(ticked);
    ok = ReportCheck(ok, "a ticked command stays ticked when chosen",
                     form.Ticks == 1 && gtk_check_menu_item_get_active(ticked) != 0
                     && form.Ticked.Checked);
    return ok;
}

/// Where a click lands, and in whose coordinates.
bool CheckMouse(ReportsForm form)
{
    bool ok = true;

    // The client area's corner in the form's window: the menu bar is above it.
    var paneCorner = PointInForm(form, form.Pane, 0, 0);
    var client = Point.FromXY(paneCorner.X - form.Pane.Left, paneCorner.Y - form.Pane.Top);

    if (!ClickFormAt(form, Point.FromXY(client.X + 600, client.Y + 400)))
    {
        ReportSkipped("where clicks go: this display cannot simulate input");
        return ok;
    }
    ok = ReportCheck(ok, "a click on the form is reported once, not "
                         + Standard.Text.FromInteger((long)form.FormDowns) + " times",
                     form.FormDowns == 1);
    ok = ReportCheck(ok, "in client coordinates, below the menu: " + FormatPoint(form.FormAt),
                     form.FormAt.X == 600 && form.FormAt.Y == 400);

    var pointer = form.GetPointerPosition();
    ok = ReportCheck(ok, "the form's pointer is in client coordinates: " + FormatPoint(pointer),
                     pointer.X == 600 && pointer.Y == 400);

    ClickFormAt(form, PointInForm(form, form.Pane, 150, 90));
    ok = ReportCheck(ok, "a click on a panel reaches the panel", form.PaneDowns == 1);
    ok = ReportCheck(ok, "in the panel's coordinates: " + FormatPoint(form.PaneAt),
                     form.PaneAt.X == 150 && form.PaneAt.Y == 90);
    ok = ReportCheck(ok, "and not the form", form.FormDowns == 1);

    pointer = form.Pane.GetPointerPosition();
    ok = ReportCheck(ok, "the panel's pointer is in its own coordinates: " + FormatPoint(pointer),
                     pointer.X == 150 && pointer.Y == 90);

    ClickFormAt(form, PointInForm(form, form.Pane, form.Box.Left + 5, form.Box.Top + 7));
    ok = ReportCheck(ok, "a click on a graphic control on a panel reaches it", form.BoxDowns == 1);
    ok = ReportCheck(ok, "in its own coordinates: " + FormatPoint(form.BoxAt),
                     form.BoxAt.X == 5 && form.BoxAt.Y == 7);
    ok = ReportCheck(ok, "and neither the panel nor the form",
                     form.PaneDowns == 1 && form.FormDowns == 1);

    ClickFormAt(form, PointInForm(form, form.Back, 5, 5));
    ok = ReportCheck(ok, "a click on a button is the button's",
                     form.BackDowns == 1 && form.FormDowns == 1);
    return ok;
}

/// The key a keystroke is, and whether it typed anything.
bool CheckKeys(ReportsForm form)
{
    bool ok = true;
    form.Entry.Focus();
    SettleEvents();

    if (!PressKeyOn(form, 0x76u, GDK_CONTROL_MASK))
    {
        ReportSkipped("what keys are: this display cannot simulate input");
        return ok;
    }
    ok = ReportCheck(ok, "Ctrl+V is the key V with Control",
                     form.LastKey == Key.V && form.LastModifiers == ModifierKeys.Control);
    ok = ReportCheck(ok, "and types nothing", form.KeyPresses == 0);

    PressKeyOn(form, 0x71u, GDK_MOD1_MASK);
    ok = ReportCheck(ok, "Alt+Q types nothing either", form.KeyPresses == 0);

    PressKeyOn(form, 0x31u, GDK_SHIFT_MASK);
    ok = ReportCheck(ok, "Shift+1 is the key 1, as Windows says: "
                         + Standard.Text.FromInteger((long)(int)form.LastKey),
                     form.LastKey == Key.D1);
    ok = ReportCheck(ok, "and types an exclamation mark",
                     form.KeyPresses == 1 && form.LastTyped == 0x21u);

    PressKeyOn(form, GDK_KEY_Shift_L, 0u);
    ok = ReportCheck(ok, "Shift alone is Shift", form.LastKey == Key.Shift);
    PressKeyOn(form, GDK_KEY_Control_L, 0u);
    ok = ReportCheck(ok, "Control alone is Control", form.LastKey == Key.Control);
    PressKeyOn(form, GDK_KEY_Caps_Lock, 0u);
    ok = ReportCheck(ok, "Caps Lock is Caps Lock", form.LastKey == Key.CapsLock);
    PressKeyOn(form, GDK_KEY_Caps_Lock, 0u);

    PressKeyOn(form, GDK_KEY_KP_0 + 1u, GDK_MOD2_MASK);
    ok = ReportCheck(ok, "keypad 1 with Num Lock is VK_NUMPAD1: "
                         + Standard.Text.FromInteger((long)(int)form.LastKey),
                     (int)form.LastKey == 97);

    // Last, because it takes the focus somewhere else.
    PressKeyOn(form, GDK_KEY_Tab, GDK_SHIFT_MASK);
    ok = ReportCheck(ok, "Shift+Tab is Tab", form.LastKey == Key.Tab);
    return ok;
}

/// A control brought to the front is drawn and hit last.
bool CheckStacking(ReportsForm form)
{
    form.Back.BringToFront();
    GtkWidget* parent = gtk_widget_get_parent(WidgetOfControl(form.Back));
    GList* children = gtk_container_get_children(parent);
    GtkWidget* last = null;
    for (GList* at = children; at != null; at = at->Next)
        last = (GtkWidget*)at->Data;
    g_list_free(children);
    return ReportCheck(true, "a button brought to the front is last among its siblings",
                       last == WidgetOfControl(form.Back));
}

/// What cairo is left able to do after a shape with no area.
bool CheckDrawing()
{
    bool ok = true;
    cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 40, 40);
    cairo_t* context = cairo_create(surface);
    var canvas = new GtkGraphicsBackend((gpointer)context);

    cairo_set_source_rgb(context, 1.0, 1.0, 1.0);
    cairo_paint(context);
    canvas.DrawRectangle(new Pen(Colors.Black, 1, PenStyle.Solid),
                         Rectangle.FromBounds(2, 2, 10, 10));
    cairo_surface_flush(surface);
    byte* pixels = cairo_image_surface_get_data(surface);
    nuint stride = (nuint)cairo_image_surface_get_stride(surface);
    ok = ReportCheck(ok, "a 10 by 10 rectangle's right edge is its tenth column",
                     pixels[5u * stride + 11u * 4u] == 0u);
    ok = ReportCheck(ok, "and nothing is drawn in the eleventh, as GDI draws it",
                     pixels[5u * stride + 12u * 4u] == 255u);
    ok = ReportCheck(ok, "and the same at the bottom",
                     pixels[11u * stride + 5u * 4u] == 0u
                     && pixels[12u * stride + 5u * 4u] == 255u);

    canvas.FillEllipse(new Brush(Colors.Red), Rectangle.FromBounds(4, 4, 0, 10));
    canvas.DrawEllipse(new Pen(Colors.Red, 1, PenStyle.Solid), Rectangle.FromBounds(4, 4, 10, 0));
    ok = ReportCheck(ok, "an ellipse with no width leaves cairo drawing",
                     cairo_status(context) == CAIRO_STATUS_SUCCESS);

    GdkPixbuf* made = gdk_pixbuf_new(0, 1, 8, 4, 4);
    g_object_ref((gpointer)made);
    var picture = new GtkBitmapBackend((gpointer)made);
    canvas.DrawBitmapIn(picture, Rectangle.FromBounds(0, 0, 0, 8));
    ok = ReportCheck(ok, "and so does a picture scaled to nothing",
                     cairo_status(context) == CAIRO_STATUS_SUCCESS);
    g_object_unref((gpointer)made);

    cairo_destroy(context);
    cairo_surface_destroy(surface);
    return ok;
}

/// A font as GTK's settings write one, read back.
bool CheckFontNames()
{
    bool ok = true;
    var fallback = new Font("Sans", 10, FontStyle.Regular);

    var half = ParsePangoFont("Ubuntu 11.5", fallback);
    ok = ReportCheck(ok, "a fractional size is a size: " + half.Family + " "
                         + Standard.Text.FromInteger((long)half.Size),
                     half.Family == "Ubuntu" && half.Size == 12);

    var light = ParsePangoFont("Ubuntu Light 10", fallback);
    ok = ReportCheck(ok, "a weight is not part of the family: " + light.Family,
                     light.Family == "Ubuntu" && light.Size == 10 && !light.Bold);

    var heavy = ParsePangoFont("Noto Sans Semi-Bold Condensed Italic 9", fallback);
    ok = ReportCheck(ok, "a heavier weight is bold, and a stretch is dropped: " + heavy.Family,
                     heavy.Family == "Noto Sans" && heavy.Size == 9 && heavy.Bold && heavy.Italic);
    return ok;
}

/// Answers the next message box as Escape would, when it appears.
class Dismisser
{
    public int Tries;
    public Dismisser() => Tries = 0;

    public void Tick(Timer sender)
    {
        Tries++;
        GList* windows = gtk_window_list_toplevels();
        for (GList* at = windows; at != null; at = at->Next)
        {
            var window = (GtkWidget*)at->Data;
            gchar* title = gtk_window_get_title(window);
            if (title != null && Standard.Text.FromNullTerminated(title) == "Dismiss me")
                gtk_dialog_response(window, -4);
        }
        g_list_free(windows);
    }
}

bool CheckMessageBox()
{
    var dismisser = new Dismisser();
    var clock = new Timer(50);
    clock.Tick += dismisser.Tick;
    clock.Start();
    var answer = Application.ShowMessage("Closed from a timer.", "Dismiss me",
                                         MessageButtons.Ok, MessageIcon.Information);
    clock.Stop();
    return ReportCheck(true, "a message box with one button closed by Escape answers Ok",
                       answer == DialogResult.Ok);
}

int CountToplevels()
{
    GList* windows = gtk_window_list_toplevels();
    int count = 0;
    for (GList* at = windows; at != null; at = at->Next)
        count++;
    g_list_free(windows);
    return count;
}

void MakeAndDropForm()
{
    var dropped = new Form(WindowBorder.Sizable);
    dropped.Text = "Dropped";
    dropped.SetBounds(0, 0, 200, 100);
}

/// A form nothing holds any more takes its window with it: its peer's
/// handlers do not keep the peer.
bool CheckDroppedForm()
{
    int before = CountToplevels();
    MakeAndDropForm();
    SettleEvents();
    return ReportCheck(true, "a dropped form's window is destroyed",
                       CountToplevels() == before);
}

/// A timer whose control is dropped stops without GLib complaining.
bool CheckDroppedTimer()
{
    var clock = new Timer(10);
    clock.Start();
    SettleEvents();
    clock = new Timer(1000);
    for (int i = 0; i < 6; i++)
        SettleEvents();
    return ReportCheck(true, "nothing GLib complained about: "
                           + Standard.Text.FromInteger((long)GlibWatch.Complaints),
                       GlibWatch.Complaints == 0);
}

#endif

int Main()
{
#if UNIX
    // Before the display opens: simulated input is core X events.
    gdk_disable_multidevice();
#endif
    Application.Initialize();
#if UNIX
    WatchGlib();
#endif
    var form = new ReportsForm();

    bool testing = false;
    var arguments = Standard.Env.GetArguments();
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        if (arguments[i] == "--selftest")
            testing = true;
    }

    if (!testing)
    {
        form.Show();
        Application.Run();
        return 0;
    }

    Console.WriteLine("Forms for Stainless -- what the platform reports");
    form.Show();
    SettleEvents();

    bool ok = CheckPortable(form);
#if UNIX
    ok = CheckUserChanges(form) && ok;
    ok = CheckMenus(form) && ok;
    ok = CheckMouse(form) && ok;
    ok = CheckKeys(form) && ok;
    ok = CheckStacking(form) && ok;
    ok = CheckDrawing() && ok;
    ok = CheckFontNames() && ok;
    ok = CheckMessageBox() && ok;
    ok = CheckDroppedForm() && ok;
    ok = CheckDroppedTimer() && ok;
#else
    ReportSkipped("the checks that drive GTK directly");
#endif

    Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
    return ok ? 0 : 1;
}
