// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// The factory: one method per peer kind, and the event loop.
//
// **`gtk_init` is called once, here, and it is the one thing this backend
// does that the Win32 one does not have to.** A Windows program has a message
// queue whether it asks for one or not; a GTK program has no display
// connection until it opens one, and every widget call before that is
// undefined. So the first `Create` initialises, which is what makes
// `Application.Initialize` enough and means a program never calls `gtk_init`
// itself.
//
// **Nothing here is registered.** The LCL needs a `TWS` class per control and
// a registration pass that runs before anything is constructed; this is a
// method per kind, and a new control that is a list with different behaviour
// needs no line in this file at all.
module Forms.Platform.Gtk;

import Standard.Collections;
import Standard.Text;
import Forms.Drawing;
import Forms;
import Forms.Platform;
import Standard.Resources;
#if UNIX
import Gtk.GLib;
import Gtk.GObject;
import Gtk.Gdk;
import Gtk.Api;
import Gtk.Cairo;
import Gtk.Signals;
import Gtk.Events;

/// The idle source `WakeEventLoop` adds: runs what other threads posted, and removes
/// itself. `G_SOURCE_REMOVE` is zero, so one wake is one drain -- and a drain
/// that finds an empty queue is the harmless case, since two wakes can arrive
/// before either source runs.
gboolean OnWakeIdle(gpointer data)
{
    Application.RunPostedWork();
    return 0;
}

/// The monitor `window` is on, or for a window not shown yet the primary one
/// -- or the first, because a compositor need not name one primary.
gpointer GetMonitorOf(gpointer window)
{
    gpointer display = gdk_display_get_default();
    if (display == null)
        return null;

    if (window != null)
    {
        gpointer found = gdk_display_get_monitor_at_window(display, (GdkWindow*)window);
        if (found != null)
            return found;
    }

    gpointer monitor = gdk_display_get_primary_monitor(display);
    if (monitor != null)
        return monitor;
    if (gdk_display_get_n_monitors(display) <= 0)
        return null;
    return gdk_display_get_monitor(display, 0);
}

/// The part of `window`'s monitor a window belongs in: all of it but a panel
/// or a dock. A display that reports an empty work area -- Broadway does --
/// has the whole monitor.
public Rectangle GetMonitorWorkArea(gpointer window)
{
    gpointer monitor = GetMonitorOf(window);
    if (monitor == null)
        return CreateRectangle(0, 0, 1024, 768);

    GdkRectangle area;
    gdk_monitor_get_workarea(monitor, &area);
    if (area.Width <= 0 || area.Height <= 0)
        gdk_monitor_get_geometry(monitor, &area);
    return CreateRectangle(area.X, area.Y, area.Width, area.Height);
}

public class GtkWidgetSet : IWidgetSet
{
    /// Whether `gtk_init` has run. A program that opens no window never pays
    /// for a display connection, which is what makes a console program that
    /// links `forms/` still start.
    bool _started;

    /// The theme's font, read once. `gtk-font-name` does not change while a
    /// program runs in any desktop that exists, and a control asks for this
    /// at every construction.
    Font? _themeFont;

    public GtkWidgetSet()
    {
        _started = false;
        _themeFont = null;
        _selfReported = new List<ClipboardRelay>();
    }

    public String Name { get { return "GTK3"; } }

    /// Opens the display connection, once.
    ///
    /// `gtk_init_check` rather than `gtk_init`, which calls `exit` when there
    /// is no display: a program with no `DISPLAY` should be told rather than
    /// vanish, and `sl_fail` is what tells it.
    void EnsureStarted()
    {
        if (_started)
            return;
        _started = true;

        int argc = 0;
        if (gtk_init_check(&argc, null) == 0)
        {
            sl_fail(("GTK could not open a display: check DISPLAY or WAYLAND_DISPLAY, " +
                     "or run under broadwayd").ToPointer());
        }
    }

    /// Subscribes a peer and puts it in its parent -- the same two steps for
    /// every control, which is why no `Create` below writes them out.
    void ConnectPeer(GtkPeer peer, IContainerPeer parent)
    {
        peer.ConnectEvents();
        parent.AddChild(peer);
    }

    // ------------------------------------------------------------ controls

    public IWindowPeer CreateWindow(IWindowNotify owner, WindowBorder border)
    {
        EnsureStarted();
        var peer = new GtkWindowPeer(owner, border);
        peer.ConnectEvents();
        return peer;
    }

    public IPushButtonPeer CreateButton(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkButtonPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public ICheckPeer CreateCheck(IControlNotify owner, IContainerPeer parent,
                                  CheckKind kind)
    {
        var peer = new GtkCheckPeer(owner, kind);
        ConnectPeer(peer, parent);
        return peer;
    }

    public ILabelPeer CreateLabel(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkLabelPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public ITextEntryPeer CreateTextEntry(IControlNotify owner, IContainerPeer parent,
                                          bool multiline)
    {
        var peer = new GtkEntryPeer(owner, multiline);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IListPeer CreateList(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkListPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IComboPeer CreateCombo(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkComboPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IGroupPeer CreateGroup(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkGroupPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IPanelPeer CreatePanel(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkPanelPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public ICustomPeer CreateCustom(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkCustomPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IScrollBarPeer CreateScrollBar(IControlNotify owner, IContainerPeer parent,
                                          bool vertical)
    {
        var peer = new GtkScrollBarPeer(owner, vertical);
        ConnectPeer(peer, parent);
        return peer;
    }

    public ISpinPeer CreateSpin(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkSpinPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public ICheckListPeer CreateCheckList(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkCheckListPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IHeaderPeer CreateHeader(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkHeaderPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IToolBarPeer CreateToolBar(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkToolBarPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IStatusBarPeer CreateStatusBar(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkStatusBarPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IProgressPeer CreateProgress(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkProgressPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public ITrackBarPeer CreateTrackBar(IControlNotify owner, IContainerPeer parent,
                                        bool vertical)
    {
        var peer = new GtkTrackBarPeer(owner, vertical);
        ConnectPeer(peer, parent);
        return peer;
    }

    public ITabControlPeer CreateTabControl(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkTabControlPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public ITreeViewPeer CreateTreeView(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkTreePeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IListViewPeer CreateListView(IControlNotify owner, IContainerPeer parent)
    {
        var peer = new GtkListViewPeer(owner);
        ConnectPeer(peer, parent);
        return peer;
    }

    public IMenuPeer CreateMenu()
    {
        EnsureStarted();
        return new GtkMenuPeer(false);
    }
    public IMenuPeer CreateMenuBar()
    {
        EnsureStarted();
        return new GtkMenuPeer(true);
    }

    public ITimerPeer CreateTimer(ITimerNotify owner)
    {
        EnsureStarted();
        return new GtkTimerPeer(owner);
    }

    // ------------------------------------------------------------ clipboard
    //
    // The work is in `Clipboard.sl` beside this file. Each starts GTK first,
    // because a clipboard belongs to a display and a program may copy before
    // it opens a window.

    public void SetClipboard(ClipboardContent content)
    {
        EnsureStarted();
        WriteClipboard(content);
        ReportOwnClipboardChange();
    }

    /// The watches this widget set reports its own copies to, on a display
    /// that cannot report them. Empty everywhere else.
    ///
    /// Posted rather than raised, as Windows posts `WM_CLIPBOARDUPDATE`: a
    /// handler that copies would otherwise be re-entered from inside its own
    /// copy.
    List<ClipboardRelay> _selfReported;

    void ReportOwnClipboardChange()
    {
        for (nuint i = _selfReported.Count; i > 0u; i--)
        {
            if (!_selfReported[i - 1u].IsAlive)
                _selfReported.RemoveAt(i - 1u);
        }

        for (nuint i = 0u; i < _selfReported.Count; i++)
        {
            var relay = _selfReported[i];
            if (relay.IsListening)
                Application.Post(() => { relay.RaiseChanged(); });
        }
    }

    public String GetClipboardText()
    {
        EnsureStarted();
        return ReadClipboardText();
    }

    public String GetClipboardHtml()
    {
        EnsureStarted();
        return ReadClipboardHtml();
    }

    public ClipboardImage? GetClipboardImage()
    {
        EnsureStarted();
        return ReadClipboardImage();
    }

    public String[] GetClipboardFiles()
    {
        EnsureStarted();
        return ReadClipboardFiles();
    }

    public byte[] GetClipboardFormat(String name)
    {
        EnsureStarted();
        return ReadClipboardTarget(name);
    }

    public bool ContainsClipboardKind(ClipboardKind kind)
    {
        EnsureStarted();
        gpointer clipboard = GetDefaultClipboard();
        switch (kind)
        {
            case ClipboardKind.Text:
                return gtk_clipboard_wait_is_text_available(clipboard) != 0;
            case ClipboardKind.Html:
                return gtk_clipboard_wait_is_target_available(clipboard, InternAtom(HtmlTarget)) != 0;
            case ClipboardKind.Image:
                return gtk_clipboard_wait_is_image_available(clipboard) != 0;
            case ClipboardKind.Files:
                return gtk_clipboard_wait_is_uris_available(clipboard) != 0;
        }
        return false;
    }

    public bool ContainsClipboardFormat(String name)
    {
        EnsureStarted();
        return gtk_clipboard_wait_is_target_available(GetDefaultClipboard(), InternAtom(name)) != 0;
    }

    public String[] GetClipboardFormatNames()
    {
        EnsureStarted();
        return ReadClipboardTargetNames();
    }

    public IClipboardWatchPeer CreateClipboardWatch(IClipboardNotify owner)
    {
        EnsureStarted();
        var relay = new ClipboardRelay(owner);
        if (!CanDisplayReportClipboardOwner())
            _selfReported.Add(relay);
        return new GtkClipboardWatchPeer(relay);
    }

    // ------------------------------------------------------------- dialogs

    public Result<String, DialogOutcome> ChooseFileToOpen(IWindowPeer? owner, String title,
                                                          String start, String[] filters)
    {
        EnsureStarted();
        return ShowOpenFileDialog(owner, title, start, filters);
    }

    public Result<String, DialogOutcome> ChooseFileToSave(IWindowPeer? owner, String title,
                                                          String start, String[] filters)
    {
        EnsureStarted();
        return ShowSaveFileDialog(owner, title, start, filters);
    }

    public Result<String, DialogOutcome> ChooseFolder(IWindowPeer? owner, String title)
    {
        EnsureStarted();
        return ShowFolderDialog(owner, title);
    }

    public Result<Color, DialogOutcome> ChooseColor(IWindowPeer? owner, Color start)
    {
        EnsureStarted();
        return ShowColorDialog(owner, start);
    }

    public Result<Font, DialogOutcome> ChooseFont(IWindowPeer? owner, Font start)
    {
        EnsureStarted();
        return ShowFontDialog(owner, start);
    }

    public DialogResult ShowMessage(IWindowPeer? owner, String text, String caption,
                                    MessageButtons buttons, MessageIcon icon)
    {
        EnsureStarted();
        return ShowMessageBox(owner, text, caption, buttons, icon);
    }

    // ------------------------------------------------------------ resources

    public IFontBackend CreateFont(Font font) => new GtkFontBackend(font);

    /// A picture from a file.
    ///
    /// **Whatever `gdk-pixbuf` has a loader for**, which on any desktop is at
    /// least PNG, JPEG, GIF and BMP -- more than the Win32 backend reads,
    /// because `LoadImageW` reads `.bmp` and nothing else. The seam says the
    /// format is the backend's business, and this is a backend taking it up.
    public Result<IBitmapBackend, String> LoadBitmap(String path)
    {
        EnsureStarted();
        GError* failed = null;
        GdkPixbuf* loaded = gdk_pixbuf_new_from_file(path.ToPointer(), &failed);

        if (loaded == null)
        {
            var why = "could not read '" + path + "'";
            if (failed != null)
            {
                if (failed->Message != null)
                {
                    why = why + ": " + Text.FromNullTerminated(failed->Message);
                }
                g_clear_error(&failed);
            }
            return Fail(why);
        }
        return Ok(new GtkBitmapBackend((gpointer)loaded));
    }

    /// A picture from pixels the caller already has.
    ///
    /// The seam hands over **blue, green, red, alpha** -- a DIB's order, and
    /// `Standard.Drawing`'s -- and gdk-pixbuf wants red first, so this swaps
    /// two bytes of each pixel on the way in. That is the whole difference
    /// between the two backends here, and it is why the seam states an order
    /// rather than saying "the platform's".
    ///
    /// The alpha stays straight: cairo composites premultiplied, but
    /// `gdk_cairo_set_source_pixbuf` does that conversion itself, so
    /// premultiplying here would apply it twice.
    public Result<IBitmapBackend, String> CreateBitmap(int width, int height, byte[] pixels)
    {
        EnsureStarted();

        if (width <= 0 || height <= 0)
            return Fail("a bitmap needs a positive width and height");

        nuint needed = (nuint)width * (nuint)height * 4u;
        if (pixels.Length < needed)
        {
            return Fail("a bitmap of " + Text.FromInteger((long)width) + "x"
                        + Text.FromInteger((long)height) + " needs "
                        + Text.FromInteger((long)needed) + " bytes and was given "
                        + Text.FromInteger((long)pixels.Length));
        }

        GdkPixbuf* made = CreatePixbufFromBgra(width, height, pixels);
        if (made == null)
            return Fail("gdk-pixbuf would not make a bitmap of that size");
        return Ok(new GtkBitmapBackend((gpointer)made));
    }

    /// A picture out of the binary's own resources, by the id the script gave.
    ///
    /// **The resource is not a file.** `rc` strips the 14-byte
    /// `BITMAPFILEHEADER` because Windows never wants it, and every decoder
    /// that is not Windows does -- so `Resources.GetBitmapFile` puts it back and
    /// what arrives here is a whole `.bmp`. Then it is fed to a
    /// `GdkPixbufLoader` rather than `gdk_pixbuf_new_from_file`, because there
    /// is no file: the bytes came out of this binary's `.rsrc` section.
    ///
    /// This used to fail on principle, on the argument that an ELF binary has
    /// no resource section. The argument was right about the *format* and wrong
    /// about the conclusion: the compiler carries the compiled script as
    /// ordinary data, so there is something to read after all.
    public Result<IBitmapBackend, String> LoadBitmapResource(int id)
    {
        EnsureStarted();

        var whole = Resources.GetBitmapFile(id);
        if (whole.Length == 0)
        {
            return Fail($"this program has no bitmap resource with id {id}");
        }

        var loader = gdk_pixbuf_loader_new();
        if (loader == null)
            return Fail("could not start an image loader");

        GError* failed = null;
        gdk_pixbuf_loader_write(loader, &whole[0u], (gsize)whole.Length, &failed);

        // The image is not complete until the loader is closed, and closing is
        // also what reports one that was truncated or not understood.
        gdk_pixbuf_loader_close(loader, &failed);

        var decoded = gdk_pixbuf_loader_get_pixbuf(loader);
        if (decoded == null)
        {
            var why = $"bitmap resource {id} could not be decoded";
            if (failed != null)
            {
                if (failed->Message != null)
                {
                    why = why + ": " + Text.FromNullTerminated(failed->Message);
                }
                g_clear_error(&failed);
            }
            g_object_unref((gpointer)loader);
            return Fail(why);
        }

        // The pixbuf belongs to the loader, so it is referenced before the
        // loader is dropped and the backend owns it from here.
        g_object_ref((gpointer)decoded);
        g_object_unref((gpointer)loader);
        if (failed != null)
            g_clear_error(&failed);

        return Ok(new GtkBitmapBackend((gpointer)decoded));
    }

    public IImageListBackend CreateImageList(Size imageSize)
    {
        return new GtkImageListBackend(imageSize);
    }

    // -------------------------------------------------------------- theme

    /// One of the theme's own colours.
    ///
    /// **Asked of the theme rather than tabulated.** GTK 3 has no
    /// `GetSysColor`: the replacements render rather than report, and the one
    /// call that still answers a colour is a lookup by the names Adwaita
    /// defines and every theme derived from it keeps. A theme that defines
    /// none of them gets the fallbacks below, which are Adwaita's own values
    /// -- so the wrong answer is still a sensible one.
    public Color GetSystemColor(SystemColorId which)
    {
        EnsureStarted();

        if (which == SystemColorId.Control)
            return LookupThemeColor("theme_bg_color", 0xF6u, 0xF5u, 0xF4u);
        if (which == SystemColorId.ControlText)
            return LookupThemeColor("theme_fg_color", 0x2Eu, 0x34u, 0x36u);
        if (which == SystemColorId.ControlDark)
            return LookupThemeColor("borders", 0xCDu, 0xC7u, 0xC2u);
        if (which == SystemColorId.ControlLight)
            return LookupThemeColor("theme_base_color", 0xFFu, 0xFFu, 0xFFu);
        if (which == SystemColorId.Window)
            return LookupThemeColor("theme_base_color", 0xFFu, 0xFFu, 0xFFu);
        if (which == SystemColorId.WindowText)
            return LookupThemeColor("theme_text_color", 0x2Eu, 0x34u, 0x36u);
        if (which == SystemColorId.Highlight)
            return LookupThemeColor("theme_selected_bg_color", 0x35u, 0x84u, 0xE4u);
        if (which == SystemColorId.HighlightText)
            return LookupThemeColor("theme_selected_fg_color", 0xFFu, 0xFFu, 0xFFu);
        return LookupThemeColor("insensitive_fg_color", 0x92u, 0x9Cu, 0x9Fu);
    }

    /// A widget whose style context the theme is read from. Any widget will
    /// do -- the named colours are the theme's rather than the widget's -- and
    /// one is kept so that a form asking for nine colours makes one widget
    /// rather than nine.
    GtkWidget* _probe;

    Color LookupThemeColor(String name, byte red, byte green, byte blue)
    {
        if (_probe == null)
            _probe = (GtkWidget*)g_object_ref_sink((gpointer)gtk_window_new(GTK_WINDOW_TOPLEVEL));

        GdkRGBA found;
        if (gtk_style_context_lookup_color(gtk_widget_get_style_context(_probe),
                                           name.ToPointer(), &found) == 0)
        {
            return Color.FromRgb(red, green, blue);
        }
        return FromRgba(found);
    }

    /// The font the desktop dresses its own dialogs in, which is what every
    /// control starts with. `gtk-font-name` is a Pango description --
    /// `"Cantarell 11"` -- so it is read apart the same way a font chooser's
    /// answer is.
    public Font GetDefaultFont()
    {
        EnsureStarted();

        var made = _themeFont;
        if (made != null)
            return (Font)made;

        var fallback = new Font("Sans", 10, FontStyle.Regular);
        gpointer settings = gtk_settings_get_default();
        if (settings == null)
        {
            _themeFont = fallback;
            return fallback;
        }

        gchar* described = null;
        g_object_get(settings, "gtk-font-name".ToPointer(), &described, null);
        if (described == null)
        {
            _themeFont = fallback;
            return fallback;
        }

        var font = ParsePangoFont(Text.FromNullTerminated(described), fallback);
        g_free((gpointer)described);
        _themeFont = font;
        return font;
    }

    // ------------------------------------------------------------- screen

    public Size ScreenSize
    {
        get
        {
            EnsureStarted();
            gpointer monitor = GetMonitorOf(null);
            if (monitor == null)
                return CreateSize(1024, 768);

            GdkRectangle area;
            gdk_monitor_get_geometry(monitor, &area);
            return CreateSize(area.Width, area.Height);
        }
    }

    public Rectangle WorkArea
    {
        get
        {
            EnsureStarted();
            return GetMonitorWorkArea(null);
        }
    }

    // --------------------------------------------------------- the loop

    public void RunEventLoop()
    {
        EnsureStarted();
        gtk_main();
    }

    /// Everything already queued, and no waiting.
    ///
    /// `gtk_main_iteration_do(0)` is one turn that does not block, so this
    /// drains the queue and returns -- which is what a program driving its own
    /// loop wants, and the reason `RunEventLoop` is not the only way in.
    ///
    /// Always true: GTK has no quit message to meet here, and `Application`
    /// remembers a quit asked for through it.
    public bool PumpEvents()
    {
        EnsureStarted();
        while (gtk_events_pending() != 0)
            gtk_main_iteration_do(0);
        return true;
    }

    /// Outside every loop there is nothing to end, and `gtk_main_quit` there
    /// is a critical warning. `Application` remembers the quit, so a `Run`
    /// that follows returns at once.
    public void QuitEventLoop()
    {
        if (gtk_main_level() > 0u)
            gtk_main_quit();
    }

    /// Adds a one-shot idle source, which the main loop runs on its own thread.
    ///
    /// GTK needs no queue of its own here and no wake window: adding a source
    /// to the main context *is* the post, and glib makes that safe from any
    /// thread. What the source does is drain `Application`'s queue, so both
    /// backends deliver the same work by the same route.
    ///
    /// Idle priority rather than default, so that a long run of posted work
    /// cannot starve redrawing -- which is the thing the posted work almost
    /// always exists to cause.
    public void WakeEventLoop()
    {
        g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, OnWakeIdle, null, null);
    }
}

#endif
