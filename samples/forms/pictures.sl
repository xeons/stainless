// SPDX-License-Identifier: 0BSD
//
// A picture that is not a `.bmp`, on a form.
//
//   stainless run samples/forms/pictures.sl forms/src bindings/win32 \
//       -l user32 -l gdi32 -l comctl32 -l comdlg32 -l ole32 -l shell32 -l advapi32
//
// `Forms.Bitmap` read `.bmp` and nothing else for as long as it existed, because
// `LoadImageW` is the whole of what Windows decodes without a library. Meanwhile
// `Standard.Drawing` decoded PNG, JPEG, BMP and GIF on both platforms and had no
// way to put any of them in a window. This is the join: a picture is drawn or
// decoded there, `Bitmap.FromImage` hands its pixels to the widget set, and an
// `Image` control shows it.
//
// The picture is *generated* rather than shipped, encoded to PNG, and decoded
// back -- so the sample needs no asset beside it and still proves the whole
// path, the encoder included. What it draws is deliberately asymmetric and
// deliberately coloured: an upside-down picture, a red-for-blue swap and a
// sheared row are the three ways this goes wrong, and each is visible at a
// glance rather than hidden behind a checksum.
//
// Pass `--selftest` and it builds the form, checks what can be checked with
// nobody in front of it, and quits. **That is not the same as looking at it.**
// A self-test here can prove a bitmap has a width; only a screenshot proves the
// picture is the right way up.
module Pictures;

import Standard.Console;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;

/// The picture the sample shows, drawn rather than loaded.
///
/// Asymmetric on purpose, in both directions and in colour:
///
///   - a **red** band across the top, so a red-for-blue swap is obvious;
///   - a **blue** band down the left, so the two axes cannot be confused;
///   - a green wedge that is wider at the bottom, so a vertical flip shows;
///   - a one-pixel white diagonal, so a wrong row stride shears visibly.
Standard.Drawing.Image? Draw(int width, int height)
{
    var made = Standard.Drawing.Image.Create(width, height);
    if (!made.Ok)
        return null;

    var picture = made.Value;
    picture.Clear(Standard.Drawing.Rgba.FromRgb((byte)32, (byte)32, (byte)40));

    picture.FillRectangle(Standard.Drawing.Rgba.FromRgb((byte)220, (byte)40, (byte)40),
                          0, 0, width, 10);
    picture.FillRectangle(Standard.Drawing.Rgba.FromRgb((byte)40, (byte)80, (byte)220),
                          0, 0, 10, height);

    for (int y = 12; y < height; y++)
    {
        int wide = ((y - 12) * (width - 14)) / (height - 12);
        picture.FillRectangle(Standard.Drawing.Rgba.FromRgb((byte)60, (byte)180, (byte)90),
                              12, y, wide, 1);
    }

    for (int i = 0; i < width && i < height; i++)
        picture.SetPixel(i, i, Standard.Drawing.Rgba.White);

    // A block that is only half there, written pixel by pixel because
    // `SetPixel` replaces where `FillRectangle` blends -- and what is wanted
    // here is an alpha of 128 surviving into the file rather than being mixed
    // into the colour underneath. It is the only part of this picture that
    // says whether the *window* blended: an opaque picture looks identical
    // whether it was alpha-blended or copied.
    for (int y = height - 46; y < height - 6; y++)
    {
        for (int x = width - 46; x < width - 6; x++)
            picture.SetPixel(x, y, Standard.Drawing.Rgba.FromArgb((byte)128, (byte)255,
                                                              (byte)220, (byte)0));
    }

    return picture;
}

public class MainForm : Form
{
    Label _said;
    Image _shown;
    Image _stretched;

    public MainForm()
    {
        base(WindowBorder.Sizable);
        Text = "A picture that is not a .bmp";
        SetBounds(0, 0, 460, 300);

        _said = new Label(this);
        _said.SetBounds(12, 12, 430, 20);

        // At its own size, centred in a box bigger than it, so `Center` is
        // visible as a margin on all four sides rather than as nothing.
        _shown = new Image(this);
        _shown.SetBounds(12, 40, 170, 180);
        _shown.Center = true;

        // Stretched into a box of the wrong shape, and proportional, so the
        // picture keeps its own and is centred in what is left. The box is
        // deliberately not 4:3 like the picture: with the same shape, the
        // property would be doing nothing and the sample would prove nothing.
        // As it is, the bars above and below are what `Proportional` bought.
        _stretched = new Image(this);
        _stretched.SetBounds(190, 40, 250, 210);
        _stretched.Stretch = true;
        _stretched.Proportional = true;

        Load();
    }

    /// Draws a picture, sends it through PNG, and shows what comes back.
    void Load()
    {
        var drawn = Draw(160, 120);
        if (drawn == null)
        {
            _said.Text = "no imaging library here: "
                         + Standard.Drawing.Imaging.BackendName;
            return;
        }

        var picture = (Standard.Drawing.Image)drawn;

        // Through the encoder and back, so this proves the decode as well as
        // the hand-over. A `FromImage` of the original would prove less and
        // look identical.
        var encoded = picture.Encode(Standard.Drawing.ImageFormat.Png);
        if (!encoded.Ok)
        {
            _said.Text = "could not encode a PNG";
            return;
        }

        var decoded = Standard.Drawing.Image.FromBytes(encoded.Value);
        if (!decoded.Ok)
        {
            _said.Text = "could not read the PNG back";
            return;
        }

        var made = Bitmap.FromImage(decoded.Value);
        if (!made.Ok)
        {
            _said.Text = made.Error;
            return;
        }

        _shown.Picture = made.Value;
        _stretched.Picture = made.Value;

        _said.Text = Standard.Drawing.Imaging.BackendName + " decoded "
                     + Standard.Text.FromInteger((long)encoded.Value.Length) + " PNG bytes into "
                     + Standard.Text.FromInteger((long)made.Value.Width) + "x"
                     + Standard.Text.FromInteger((long)made.Value.Height);
    }

    /// What can be answered without a person in front of it -- which is the
    /// model, and never the view. See the note at the top.
    public bool SelfTest()
    {
        bool ok = true;

        ok = Check(ok, "an imaging library is here",
                   Standard.Drawing.Imaging.Available);

        var shown = _shown.Picture;
        ok = Check(ok, "a PNG became a bitmap", shown != null);

        if (shown != null)
        {
            var picture = (Bitmap)shown;
            ok = Check(ok, "at the size it was drawn",
                       picture.Width == 160 && picture.Height == 120);
            ok = Check(ok, "and the platform took it", picture.Backend().Handle != 0u);
        }

        ok = Check(ok, "both controls show it",
                   _stretched.Picture != null && _stretched.Stretch);
        ok = Check(ok, "one centred, one proportional",
                   _shown.Center && _stretched.Proportional);

        return ok;
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
        Application.Drain();
        bool ok = form.SelfTest();
        Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
        return ok ? 0 : 1;
    }

    Application.Run();
    return 0;
}
