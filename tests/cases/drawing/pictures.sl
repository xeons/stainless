// Standard.Drawing, against whichever imaging library this machine has.
//
// **Needs one.** GDI+ is part of Windows; libgd is a package, and a machine
// without it fails this case rather than skipping it, which is the honest
// outcome for a suite that is meant to notice.
//
// Nothing here asserts an antialiased pixel. GDI+ and libgd are two rasterisers
// and their edges differ by a shade, which is a real difference and not one a
// test should pin; what both agree about exactly is a pixel well inside a
// filled shape, a size, a round trip and an error.
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
