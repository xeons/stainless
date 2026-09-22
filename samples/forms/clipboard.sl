// SPDX-License-Identifier: 0BSD
//
// Every format the clipboard carries, both ways.
//
//   stainless run samples/forms/clipboard.sl forms/src bindings/win32 \
//       -l user32 -l gdi32 -l comctl32 -l comdlg32 -l ole32 -l shell32 -l advapi32
//
// Copy from here and paste into another program, or the other way round: the
// buttons put text, HTML, a picture, a list of files and a format of this
// program's own on the clipboard, and the list on the right is what the
// clipboard holds now, refreshed by a `ClipboardWatcher` whenever anything on
// the desktop changes it. Paste a picture from anywhere and it is shown.
//
// Pass `--selftest` and it round-trips every format, checks that the watcher
// heard each change, and puts back whatever text the clipboard held before.
module ClipboardSample;

import Standard.Console;
import Standard.Text;
import Standard.Threading;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if WINDOWS
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
#endif

/// The name this program's own format goes by.
static readonly String ShapesFormat = "application/x-stainless-shapes";

/// A small picture whose every pixel differs, and one of them half there, so
/// a round trip that flipped, swapped or flattened it would not compare equal.
///
/// The half is 129 rather than 128 because libgd keeps seven bits of alpha,
/// and 129 is one of the values it holds exactly.
byte[] SamplePixels()
{
    var pixels = new byte[3u * 2u * 4u];
    for (nuint i = 0u; i < 6u; i++)
    {
        pixels[i * 4u] = (byte)(i * 40u);           // blue
        pixels[i * 4u + 1u] = (byte)(200u - i * 30u); // green
        pixels[i * 4u + 2u] = (byte)(i * 17u + 5u);  // red
        pixels[i * 4u + 3u] = (byte)255;
    }
    pixels[4u * 4u + 3u] = (byte)129;
    return pixels;
}

public class MainForm : Form
{
    TextBox _editor;
    TextBox _lines;
    ListBox _formats;
    Label _said;
    Image _pasted;
    ClipboardWatcher _watcher;
    int _changes;

    public MainForm()
    {
        base(WindowBorder.Sizable);
        Text = "Clipboard";
        SetBounds(0, 0, 620, 420);

        _editor = new TextBox(this);
        _editor.SetBounds(12, 12, 280, 24);
        _editor.Text = "Select some of this and cut, copy or paste";

        _lines = new TextBox(this, true);
        _lines.SetBounds(12, 44, 280, 70);
        _lines.Text = "alpha beta gamma";

        AddButton("Cut", 12, 122, this.OnCut);
        AddButton("Copy", 106, 122, this.OnCopy);
        AddButton("Paste", 200, 122, this.OnPaste);

        AddButton("Copy HTML", 12, 160, this.OnCopyHtml);
        AddButton("Copy picture", 106, 160, this.OnCopyPicture);
        AddButton("Copy files", 200, 160, this.OnCopyFiles);

        AddButton("Copy all", 12, 198, this.OnCopyAll);
        AddButton("Copy text", 106, 198, this.OnCopyText);
        AddButton("Clear", 200, 198, this.OnClear);

        _pasted = new Image(this);
        _pasted.SetBounds(12, 240, 280, 130);
        _pasted.Stretch = true;
        _pasted.Proportional = true;

        _formats = new ListBox(this);
        _formats.SetBounds(310, 12, 290, 330);

        _said = new Label(this);
        _said.SetBounds(310, 350, 290, 20);

        _changes = 0;
        _watcher = new ClipboardWatcher();
        _watcher.Changed += this.OnClipboardChanged;
        ShowFormats();
    }

    void AddButton(String caption, int x, int y, EventHandler handler)
    {
        var button = new Button(this);
        button.Text = caption;
        button.SetBounds(x, y, 88, 30);
        button.Click += handler;
    }

    /// The last box the user was in, which is what Cut, Copy and Paste act on.
    TextBoxBase Target => _lines.Focused ? (TextBoxBase)_lines : (TextBoxBase)_editor;

    void OnCut(Control sender) => Target.CutToClipboard();
    void OnCopy(Control sender) => Target.CopyToClipboard();
    void OnPaste(Control sender) => Target.PasteFromClipboard();

    void OnCopyHtml(Control sender)
    {
        Clipboard.SetHtml("<p>Copied from <b>Stainless</b></p>", "Copied from Stainless");
    }

    void OnCopyPicture(Control sender)
    {
        var made = Standard.Drawing.Image.FromBgra(3, 2, SamplePixels());
        if (made.Ok)
            Clipboard.SetImage(made.Value);
    }

    void OnCopyFiles(Control sender) => Clipboard.SetFiles(SampleFiles());

    void OnCopyAll(Control sender)
    {
        var data = new ClipboardData();
        data.Text = "three shapes";
        data.Html = "<i>three</i> shapes";
        data.SetData(ShapesFormat, "circle,square,star".ToBytes());
        Clipboard.SetDataObject(data);
    }

    void OnCopyText(Control sender) => Clipboard.SetText(_editor.Text);

    void OnClear(Control sender) => Clipboard.Clear();

    /// Lists what is on offer now, and shows a picture if one of them is.
    void OnClipboardChanged(ClipboardWatcher sender)
    {
        _changes++;
        ShowFormats();
        if (Clipboard.HasImage)
            _pasted.Picture = Clipboard.GetBitmap();
    }

    void ShowFormats()
    {
        _formats.Clear();
        var names = Clipboard.GetFormats();
        for (nuint i = 0u; i < names.Length; i++)
            _formats.Add(names[i]);
        _said.Text = Standard.Text.FromInteger((long)_changes) + " changes seen";
    }

    /// Absolute paths, with a space and a letter outside ASCII in one of them,
    /// which is where an encoding mistake would show. Nothing is read, so they
    /// need not exist.
    static String[] SampleFiles()
    {
        var paths = new String[2u];
#if WINDOWS
        paths[0u] = "C:\\Stainless\\notes.txt";
        paths[1u] = "C:\\Stainless\\a folder\\naïve.png";
#else
        paths[0u] = "/tmp/stainless/notes.txt";
        paths[1u] = "/tmp/stainless/a folder/naïve.png";
#endif
        return paths;
    }

    // ------------------------------------------------------------ self test

    /// Runs the loop until `_changes` passes `seen` or a second goes by. The
    /// watcher is told by a message, so nothing arrives until the loop turns.
    bool HeardChangeAfter(int seen)
    {
        for (int i = 0; i < 100 && _changes <= seen; i++)
        {
            Application.DoEvents();
            Sleep(10u);
        }
        return _changes > seen;
    }

    /// Lets a paste that GTK delivers through the main loop arrive.
    void Settle()
    {
        for (int i = 0; i < 10; i++)
        {
            Application.DoEvents();
            Sleep(10u);
        }
    }

    public bool SelfTest()
    {
        bool ok = true;

        // The clipboard belongs to the whole desktop, so whatever text was on
        // it goes back afterwards rather than being replaced by a test's
        // leavings.
        String was = Clipboard.GetText();

        // Text.
        int seen = _changes;
        Clipboard.SetText("plain text, with ✓ in it");
        ok = Check(ok, "text is on offer", Clipboard.HasText);
        ok = Check(ok, "text comes back", Clipboard.GetText() == "plain text, with ✓ in it");
        ok = Check(ok, "the watcher heard it", HeardChangeAfter(seen));

        // HTML beside text.
        Clipboard.SetHtml("<b>bold</b> &amp; more", "bold & more");
        ok = Check(ok, "HTML is on offer", Clipboard.HasHtml);
        ok = Check(ok, "the fragment comes back", Clipboard.GetHtml() == "<b>bold</b> &amp; more");
        ok = Check(ok, "and the text beside it", Clipboard.GetText() == "bold & more");

        // A picture.
        var made = Standard.Drawing.Image.FromBgra(3, 2, SamplePixels());
        ok = Check(ok, "an image is made from pixels", made.Ok);
        if (made.Ok)
        {
            ok = Check(ok, "and keeps them", SamePixels(made.Value.ToBgra(), SamplePixels()));

            Clipboard.SetImage(made.Value);
            ok = Check(ok, "a picture is on offer", Clipboard.HasImage);
            ok = Check(ok, "and no text", !Clipboard.HasText);

            var back = Clipboard.GetImage();
            ok = Check(ok, "the picture comes back", back != null);
            if (back != null)
            {
                var picture = (Standard.Drawing.Image)back;
                ok = Check(ok, "at its size", picture.Width == 3 && picture.Height == 2);
                ok = Check(ok, "pixel for pixel, alpha included",
                           SamePixels(picture.ToBgra(), SamplePixels()));
            }

            var shown = Clipboard.GetBitmap();
            ok = Check(ok, "and as a bitmap", shown != null
                       && ((Bitmap)shown).Width == 3 && ((Bitmap)shown).Height == 2);
        }

#if WINDOWS
        ok = Check(ok, "a bitmap another program copied is read the right way up",
                   ForeignBitmapReadsBack());
#endif

        // Files.
        var files = SampleFiles();
        Clipboard.SetFiles(files);
        ok = Check(ok, "files are on offer", Clipboard.HasFiles);
        var pasted = Clipboard.GetFiles();
        ok = Check(ok, "the paths come back", pasted.Length == 2u
                   && pasted[0u] == files[0u] && pasted[1u] == files[1u]);

        // A format of this program's own.
        var shapes = new byte[5u];
        shapes[0u] = (byte)1;
        shapes[1u] = (byte)2;
        shapes[2u] = (byte)0;
        shapes[3u] = (byte)255;
        shapes[4u] = (byte)7;
        Clipboard.SetData(ShapesFormat, shapes);
        ok = Check(ok, "a named format is on offer", Clipboard.HasFormat(ShapesFormat));
        var bytes = Clipboard.GetData(ShapesFormat);
        ok = Check(ok, "its bytes come back", bytes.Length >= 5u && bytes[0u] == (byte)1
                   && bytes[2u] == (byte)0 && bytes[3u] == (byte)255 && bytes[4u] == (byte)7);

        // Several at once.
        seen = _changes;
        OnCopyAll(this);
        ok = Check(ok, "one copy offers text", Clipboard.GetText() == "three shapes");
        ok = Check(ok, "and HTML", Clipboard.GetHtml() == "<i>three</i> shapes");
        ok = Check(ok, "and its own format", Clipboard.HasFormat(ShapesFormat));
        ok = Check(ok, "and not what it did not set", !Clipboard.HasImage && !Clipboard.HasFiles);
        ok = Check(ok, "the formats are listed", Clipboard.GetFormats().Length >= 3u);
        ok = Check(ok, "the watcher heard that too", HeardChangeAfter(seen));
        ok = Check(ok, "and listed what it saw", _formats.Count >= 3u);

        // Emptying it.
        Clipboard.Clear();
        ok = Check(ok, "a cleared clipboard offers nothing",
                   !Clipboard.HasText && !Clipboard.HasHtml
                   && !Clipboard.HasFormat(ShapesFormat) && Clipboard.GetText() == "");

        // A text box's own commands.
        _editor.Text = "hello world";
        _editor.SelectionStart = 6;
        _editor.SelectionLength = 5;
        _editor.CopyToClipboard();
        ok = Check(ok, "a box copies its selection", Clipboard.GetText() == "world");

        _editor.CutToClipboard();
        Settle();
        ok = Check(ok, "and cuts it", _editor.Text == "hello "
                   && Clipboard.GetText() == "world");

        _editor.SelectionStart = 6;
        _editor.SelectionLength = 0;
        _editor.PasteFromClipboard();
        Settle();
        ok = Check(ok, "and pastes it back", _editor.Text == "hello world");

        _lines.Text = "alpha beta gamma";
        _lines.SelectionStart = 6;
        _lines.SelectionLength = 4;
        ok = Check(ok, "a multi-line box reports its selection",
                   _lines.SelectionStart == 6 && _lines.SelectionLength == 4);
        _lines.CopyToClipboard();
        ok = Check(ok, "and copies it", Clipboard.GetText() == "beta");

        _lines.SelectionStart = 0;
        _lines.SelectionLength = 6;
        _lines.CutToClipboard();
        Settle();
        ok = Check(ok, "and cuts it", _lines.Text == "beta gamma"
                   && Clipboard.GetText() == "alpha ");

        if (was.IsEmpty)
        {
            Clipboard.Clear();
        }
        else
        {
            Clipboard.SetText(was);
        }
        return ok;
    }

#if WINDOWS
    /// Puts a picture on the clipboard as .NET and most Windows programs do --
    /// a `CF_DIB` with bit-field masks and nothing else -- and reads it back.
    ///
    /// Windows then synthesises the `CF_DIBV5` this library reads first, and
    /// lays the masks out twice in it; a reader that trusts the header's size
    /// sees every pixel three places to the left.
    bool ForeignBitmapReadsBack()
    {
        // 2x2, bottom-up: the file's first row is the picture's last.
        var dib = new byte[40u + 12u + 16u];
        dib[0u] = (byte)40;
        dib[4u] = (byte)2;
        dib[8u] = (byte)2;
        dib[12u] = (byte)1;
        dib[14u] = (byte)32;
        dib[16u] = (byte)3;
        dib[20u] = (byte)16;
        dib[42u] = (byte)0xFF;                     // red mask 0x00FF0000
        dib[45u] = (byte)0xFF;                     // green mask 0x0000FF00
        dib[48u] = (byte)0xFF;                     // blue mask 0x000000FF
        dib[52u + 8u + 2u] = (byte)0xFF;           // top-left red
        dib[52u + 12u] = (byte)0xFF;               // top-right blue
        dib[52u + 1u] = (byte)0xFF;                // bottom-left green
        for (nuint i = 3u; i < 16u; i = i + 4u)
            dib[52u + i] = (byte)0xFF;

        HGLOBAL block = GlobalAlloc(GlobalMoveable, dib.Length);
        byte* into = (byte*)GlobalLock(block);
        for (nuint i = 0u; i < dib.Length; i++)
            into[i] = dib[i];
        GlobalUnlock(block);

        if (OpenClipboard(null) == 0)
        {
            GlobalFree(block);
            return false;
        }
        EmptyClipboard();
        SetClipboardData(ClipboardDib, block);
        CloseClipboard();

        var back = Clipboard.GetImage();
        if (back == null)
            return false;
        var picture = (Standard.Drawing.Image)back;
        var topLeft = picture.GetPixel(0, 0);
        var topRight = picture.GetPixel(1, 0);
        var bottomLeft = picture.GetPixel(0, 1);
        return topLeft.R == (byte)255 && topLeft.B == (byte)0 && topLeft.A == (byte)255
            && topRight.B == (byte)255 && topRight.R == (byte)0
            && bottomLeft.G == (byte)255 && bottomLeft.R == (byte)0;
    }
#endif

    static bool SamePixels(byte[] got, byte[] wanted)
    {
        if (got.Length != wanted.Length)
            return false;
        for (nuint i = 0u; i < got.Length; i++)
        {
            if (got[i] != wanted[i])
                return false;
        }
        return true;
    }

    bool Check(bool running, String what, bool passed)
    {
        Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
        return running && passed;
    }
}

int Main(String[] arguments)
{
    Application.Initialize();

    var form = new MainForm();
    form.CenterOnScreen();

    bool testing = false;
    for (nuint i = 0u; i < arguments.Length; i++)
    {
        if (arguments[i] == "--selftest")
            testing = true;
    }

    form.Show();

    if (testing)
    {
        Application.RunPostedWork();
        bool ok = form.SelfTest();
        Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
        return ok ? 0 : 1;
    }

    Application.Run();
    return 0;
}
