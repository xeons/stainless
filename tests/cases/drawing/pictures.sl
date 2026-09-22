// Standard.Drawing, against whichever imaging library this machine has.
//
// **Needs one.** GDI+ is part of Windows; libgd is a package, and a machine
// without it fails this case rather than skipping it, which is the honest
// outcome for a suite that is meant to notice.
//
// Nothing here asserts the shade of an antialiased pixel. GDI+ and libgd are
// two rasterisers and a curved edge differs between them by a shade, which is a
// real difference and not one a test should pin. What both MUST agree about
// exactly is which pixels a shape touches at all, a pixel well inside it, a
// size, a round trip and an error.
module Pictures;

import Standard.Console;
import Standard.Drawing;

int Main()
{
    bool ok = true;

    ok = Check(ok, "an imaging library is here", Imaging.Available);
    ok = Check(ok, "and it has a name", !Imaging.BackendName.IsEmpty);

    // ---- making one.
    var made = Image.Create(64, 48);
    ok = Check(ok, "a picture is made", made.Ok);
    if (!made.Ok)
        return Done(false);

    var picture = made.Value;
    ok = Check(ok, "at the size asked for", picture.Width == 64 && picture.Height == 48);
    ok = Check(ok, "and starts empty", picture.GetPixel(0, 0).IsInvisible);

    // A size that is not a size is refused rather than guessed at.
    var refused = Image.Create(0, 10);
    ok = Check(ok, "a zero width is refused",
               refused.Fail && refused.Error == ImageError.Invalid);

    // ---- drawing.
    picture.Clear(Rgba.White);
    var cleared = picture.GetPixel(1, 1);
    ok = Check(ok, "a clear reaches every pixel",
               cleared.R == (byte)255 && cleared.G == (byte)255
               && cleared.B == (byte)255 && cleared.A == (byte)255);

    picture.FillRectangle(Rgba.Rgb((byte)200, (byte)30, (byte)30), 8, 8, 24, 16);
    var inside = picture.GetPixel(20, 16);
    ok = Check(ok, "a filled rectangle is filled",
               inside.R == (byte)200 && inside.G == (byte)30 && inside.B == (byte)30);

    var beside = picture.GetPixel(40, 16);
    ok = Check(ok, "and stops where it was told",
               beside.R == (byte)255 && beside.G == (byte)255 && beside.B == (byte)255);

    picture.FillEllipse(Rgba.Blue, 36, 8, 20, 16);
    var middle = picture.GetPixel(46, 16);
    ok = Check(ok, "a filled ellipse is filled",
               middle.B == (byte)255 && middle.R == (byte)0);

    int[] triangle = new int[6];
    triangle[0u] = 8;  triangle[1u] = 44;
    triangle[2u] = 32; triangle[3u] = 30;
    triangle[4u] = 56; triangle[5u] = 44;
    picture.FillPolygon(Rgba.Black, triangle);
    var point = picture.GetPixel(32, 41);
    ok = Check(ok, "a filled polygon is filled",
               point.R == (byte)0 && point.G == (byte)0 && point.B == (byte)0);

    // A polygon needs three points, and two is a mistake rather than a crash.
    int[] tooFew = new int[4];
    picture.FillPolygon(Rgba.Red, tooFew);
    ok = Check(ok, "two points draw nothing",
               picture.GetPixel(0, 0).R == (byte)255);

    // ---- pixels.
    picture.SetPixel(2, 2, Rgba.Argb((byte)128, (byte)10, (byte)20, (byte)30));
    var written = picture.GetPixel(2, 2);
    ok = Check(ok, "a written pixel reads back",
               written.R == (byte)10 && written.G == (byte)20 && written.B == (byte)30);
    // Not the alpha: libgd keeps seven bits of it, so 128 comes back as 129.
    ok = Check(ok, "and keeps roughly its alpha",
               written.A > (byte)120 && written.A < (byte)136);

    // Whatever libgd rounded it to on the first trip, a second trip MUST
    // leave alone.
    picture.SetPixel(2, 2, written);
    ok = Check(ok, "and an alpha that has been through once stays put",
               picture.GetPixel(2, 2).A == written.A);

    ok = Check(ok, "a pixel outside is transparent",
               picture.GetPixel(-1, 0).IsInvisible
               && picture.GetPixel(0, 999).IsInvisible);

    // ---- the round trip, which is what says the bytes are a real PNG rather
    // than a buffer of a plausible length.
    var encoded = picture.Encode(ImageFormat.Png);
    ok = Check(ok, "it encodes", encoded.Ok);
    if (!encoded.Ok)
        return Done(false);

    ok = Check(ok, "to more than a header", encoded.Value.Length > 100u);
    ok = Check(ok, "with a PNG's first bytes",
               encoded.Value[0u] == (byte)0x89 && encoded.Value[1u] == (byte)0x50);

    var back = Image.FromBytes(encoded.Value);
    ok = Check(ok, "and decodes again", back.Ok);
    if (!back.Ok)
        return Done(false);

    ok = Check(ok, "at the same size",
               back.Value.Width == 64 && back.Value.Height == 48);
    var survived = back.Value.GetPixel(20, 16);
    ok = Check(ok, "with the drawing still in it",
               survived.R == (byte)200 && survived.G == (byte)30 && survived.B == (byte)30);

    // ---- a thumbnail.
    var small = picture.Resize(16, 12);
    ok = Check(ok, "it resizes", small.Ok && small.Value.Width == 16
                                 && small.Value.Height == 12);

    // ---- drawing one picture on another.
    var sheet = Image.Create(64, 48);
    if (sheet.Ok)
    {
        sheet.Value.Clear(Rgba.Black);
        sheet.Value.Draw(picture, 0, 0);
        var copied = sheet.Value.GetPixel(20, 16);
        ok = Check(ok, "one picture draws on another",
                   copied.R == (byte)200 && copied.G == (byte)30 && copied.B == (byte)30);
    }

    // ---- every pixel at once.
    var pixels = new byte[picture.PixelByteLength];
    bool copied = picture.CopyPixels(pixels);
    ok = Check(ok, "every pixel reads out at once", copied);
    ok = Check(ok, "as four bytes a pixel",
               picture.Stride == 256u && picture.PixelByteLength == 12288u);

    // The filled rectangle covers (20, 16), which is row 16 column 20.
    nuint at = picture.Stride * 16u + 80u;
    ok = Check(ok, "in blue, green, red, alpha order",
               pixels[at] == (byte)30 && pixels[at + 1u] == (byte)30
               && pixels[at + 2u] == (byte)200 && pixels[at + 3u] == (byte)255);

    var again = picture.ToBgra();
    ok = Check(ok, "and the same the other way",
               again.Length == picture.PixelByteLength && again[at + 2u] == (byte)200);

    ok = Check(ok, "a buffer too small is refused",
               !picture.CopyPixels(new byte[16u]));

    // ---- and back in.
    var rebuilt = Image.FromBgra(64, 48, pixels);
    ok = Check(ok, "a picture is made from pixels", rebuilt.Ok);
    if (rebuilt.Ok)
    {
        var out = rebuilt.Value.ToBgra();
        ok = Check(ok, "and gives the same ones back",
                   out.Length == pixels.Length && out[at] == (byte)30
                   && out[at + 2u] == (byte)200 && out[at + 3u] == (byte)255);
    }

    ok = Check(ok, "too few pixels are refused",
               Image.FromBgra(64, 48, new byte[16u]).Fail);

    ok = Edges(ok);
    ok = Scaling(ok);

    // ---- what goes wrong.
    var missing = Image.FromFile("no-such-picture-anywhere.png");
    ok = Check(ok, "a missing file says so",
               missing.Fail && missing.Error == ImageError.NotFound);

    var rubbish = new byte[8];
    var unknown = Image.FromBytes(rubbish);
    ok = Check(ok, "and bytes that are not a picture say so",
               unknown.Fail && unknown.Error == ImageError.Unsupported);

    var empty = Image.FromBytes(new byte[0u]);
    ok = Check(ok, "and no bytes at all",
               empty.Fail && empty.Error == ImageError.Invalid);

    return Done(ok);
}

/// A fresh transparent picture, or null when one cannot be made.
Image? MakeBlankPicture(int width, int height)
{
    var made = Image.Create(width, height);
    if (!made.Ok)
        return null;
    return made.Value;
}

bool IsOpaqueRed(Rgba colour)
{
    return colour.R == (byte)255 && colour.G == (byte)0 && colour.B == (byte)0
           && colour.A == (byte)255;
}

// ---- edges. A fill covers exactly the pixels it was given, and a one-pixel
// outline sits on its first and last, on both backends.
bool Edges(bool ok)
{
    var held = MakeBlankPicture(20, 20);
    if (held == null)
        return Check(ok, "a picture for the edges", false);
    var box = (Image)held;

    box.FillRectangle(Rgba.Red, 5, 5, 10, 10);
    ok = Check(ok, "a fill covers its first row and column",
               IsOpaqueRed(box.GetPixel(5, 7)) && IsOpaqueRed(box.GetPixel(7, 5)));
    ok = Check(ok, "and its last",
               IsOpaqueRed(box.GetPixel(14, 7)) && IsOpaqueRed(box.GetPixel(7, 14)));
    ok = Check(ok, "and nothing either side",
               box.GetPixel(4, 7).IsInvisible && box.GetPixel(15, 7).IsInvisible
               && box.GetPixel(7, 4).IsInvisible && box.GetPixel(7, 15).IsInvisible);

    var line = (Image)MakeBlankPicture(20, 20);
    line.DrawRectangle(Rgba.Red, 2, 2, 6, 6);
    ok = Check(ok, "an outline is on its first and last pixels",
               IsOpaqueRed(line.GetPixel(2, 4)) && IsOpaqueRed(line.GetPixel(7, 4))
               && IsOpaqueRed(line.GetPixel(4, 2)) && IsOpaqueRed(line.GetPixel(4, 7)));
    ok = Check(ok, "and nowhere beside them",
               line.GetPixel(1, 4).IsInvisible && line.GetPixel(8, 4).IsInvisible
               && line.GetPixel(3, 4).IsInvisible && line.GetPixel(4, 8).IsInvisible);

    // Only an odd size has a middle pixel, so only an odd ellipse can reach
    // both sides of its rectangle. An even one MUST still stay inside it.
    var even = (Image)MakeBlankPicture(20, 20);
    even.FillEllipse(Rgba.Red, 0, 0, 10, 10);
    ok = Check(ok, "an even ellipse stays inside its rectangle",
               IsOpaqueRed(even.GetPixel(5, 5))
               && even.GetPixel(10, 5).IsInvisible && even.GetPixel(5, 10).IsInvisible);

    var odd = (Image)MakeBlankPicture(20, 20);
    odd.FillEllipse(Rgba.Red, 0, 0, 11, 11);
    ok = Check(ok, "an odd ellipse reaches every side of it",
               !odd.GetPixel(0, 5).IsInvisible && !odd.GetPixel(10, 5).IsInvisible
               && !odd.GetPixel(5, 0).IsInvisible && !odd.GetPixel(5, 10).IsInvisible);
    ok = Check(ok, "and no further",
               odd.GetPixel(11, 5).IsInvisible && odd.GetPixel(5, 11).IsInvisible);

    var ring = (Image)MakeBlankPicture(20, 20);
    ring.DrawEllipse(Rgba.Red, 0, 0, 10, 10);
    ok = Check(ok, "an outlined ellipse stays inside its rectangle",
               ring.GetPixel(10, 5).IsInvisible && ring.GetPixel(5, 10).IsInvisible
               && ring.GetPixel(5, 5).IsInvisible);
    return ok;
}

// ---- scaling. The last row and column come from the source's last, rather
// than from a blend with whatever lies past it.
bool Scaling(bool ok)
{
    var held = MakeBlankPicture(10, 10);
    if (held == null)
        return Check(ok, "a picture to scale", false);
    var small = (Image)held;
    small.Clear(Rgba.Red);

    var grown = small.Resize(20, 20);
    ok = Check(ok, "a resize keeps its corners",
               grown.Ok && IsOpaqueRed(grown.Value.GetPixel(0, 0))
               && IsOpaqueRed(grown.Value.GetPixel(19, 0))
               && IsOpaqueRed(grown.Value.GetPixel(0, 19))
               && IsOpaqueRed(grown.Value.GetPixel(19, 19)));

    var shrunk = small.Resize(5, 5);
    ok = Check(ok, "and so does a shrink",
               shrunk.Ok && IsOpaqueRed(shrunk.Value.GetPixel(4, 4)));

    var target = (Image)MakeBlankPicture(30, 30);
    target.Draw(small, 5, 5);
    ok = Check(ok, "a picture drawn at its own size lands where it was put",
               IsOpaqueRed(target.GetPixel(5, 5)) && IsOpaqueRed(target.GetPixel(14, 14))
               && target.GetPixel(4, 4).IsInvisible && target.GetPixel(15, 15).IsInvisible);
    return ok;
}

int Done(bool ok)
{
    Console.WriteLine(ok ? "all checks passed" : "checks FAILED");
    return ok ? 0 : 1;
}

bool Check(bool running, String what, bool passed)
{
    Console.WriteLine((passed ? "  ok   " : "  FAIL ") + what);
    return running && passed;
}
