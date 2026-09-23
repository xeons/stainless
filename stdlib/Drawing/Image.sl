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

module Standard.Drawing;

import Standard.Collections;
import Standard.Text;
import Standard.File;
import Standard.IO;

// ==================================================================== image

/// A picture in memory.
///
/// **The handle is released by the destructor**, so an image is closed when the
/// last reference to it goes and there is no `Dispose` to forget. That is worth
/// stating because the thing being released is a GDI+ or libgd object rather
/// than memory the language allocated -- ARC counts the `Image`, and the
/// `Image` owns the picture.
public sealed class Image
{
    void* _handle;
    int _wide;
    int _high;

    Image(void* made, int width, int height)
    {
        _handle = made;
        _wide = width;
        _high = height;
    }

    ~Image()
    {
        if (_handle == null)
            return;
        var backend = Imaging.CurrentBackend;
        if (backend != null)
            ((Backend)backend).DestroyImage(_handle);
        _handle = null;
    }

    // ------------------------------------------------------------- making one

    /// An empty picture, every pixel transparent.
    ///
    /// @failure ImageError.NoBackend    there is no imaging library on this
    ///                                  machine
    /// @failure ImageError.OutOfMemory  the backend would not make a picture
    ///                                  that big
    /// @failure ImageError.Invalid      a width or a height that is not
    ///                                  positive
    public static Result<Image, ImageError> Create(int width, int height)
    {
        if (width <= 0 || height <= 0)
            return Fail(ImageError.Invalid);

        var backend = Imaging.CurrentBackend;
        if (backend == null)
            return Fail(ImageError.NoBackend);

        void* made = ((Backend)backend).CreateImage(width, height);
        if (made == null)
            return Fail(ImageError.OutOfMemory);
        return Ok(new Image(made, width, height));
    }

    /// A picture decoded from bytes, whatever of the four formats they hold.
    ///
    /// @failure ImageError.NoBackend    there is no imaging library on this
    ///                                  machine
    /// @failure ImageError.Unreadable   the format was recognised and the
    ///                                  decoder would not have the bytes
    /// @failure ImageError.Unsupported  the first bytes are none of the four,
    ///                                  or name a format this backend was
    ///                                  built without
    /// @failure ImageError.Invalid      there are no bytes
    /// @see Image.FromFile
    public static Result<Image, ImageError> FromBytes(byte[] data)
    {
        if (data.Length == 0u)
            return Fail(ImageError.Invalid);

        var backend = Imaging.CurrentBackend;
        if (backend == null)
            return Fail(ImageError.NoBackend);

        ImageFormat format = ImageFormat.Png;
        if (!SniffFormat(data, &format) || !((Backend)backend).CanDecode(format))
            return Fail(ImageError.Unsupported);

        void* made = ((Backend)backend).DecodeImage(data);
        if (made == null)
            return Fail(ImageError.Unreadable);

        var found = (Backend)backend;
        return Ok(new Image(made, found.GetWidth(made), found.GetHeight(made)));
    }

    /// A picture read from a file.
    ///
    /// The bytes are read here rather than handed to the decoder, so that a
    /// missing file is `NotFound` on both platforms rather than whatever each
    /// library says about one it could not open.
    ///
    /// @failure ImageError.NoBackend    there is no imaging library on this
    ///                                  machine
    /// @failure ImageError.NotFound     there is no file at that path
    /// @failure ImageError.Unreadable   the file could not be read, or the
    ///                                  decoder would not have it
    /// @failure ImageError.Unsupported  the first bytes are none of the four,
    ///                                  or name a format this backend was
    ///                                  built without
    /// @failure ImageError.Invalid      the file is empty
    /// @see Image.Save
    public static Result<Image, ImageError> FromFile(String path)
    {
        var read = ReadAllBytes(path);
        if (!read.Ok)
        {
            return Fail(read.Error == IOError.NotFound
                        ? ImageError.NotFound : ImageError.Unreadable);
        }
        return FromBytes(read.Value);
    }

    /// A picture made from pixels in `CopyPixels`' order: blue, green, red and
    /// straight alpha, rows top to bottom, `width * 4` bytes to a row.
    ///
    /// What a clipboard or a capture hands back. The bytes are copied, so the
    /// array may change afterwards without changing the picture.
    ///
    /// @failure ImageError.NoBackend    there is no imaging library on this
    ///                                  machine
    /// @failure ImageError.OutOfMemory  the backend would not make a picture
    ///                                  that big, or refused the pixels
    /// @failure ImageError.Invalid      a width or a height that is not
    ///                                  positive, or fewer than `width *
    ///                                  height * 4` bytes
    /// @see Image.CopyPixels
    public static Result<Image, ImageError> FromBgra(int width, int height, byte[] pixels)
    {
        if (width <= 0 || height <= 0)
            return Fail(ImageError.Invalid);
        if (pixels.Length < (nuint)width * (nuint)height * 4u)
            return Fail(ImageError.Invalid);

        var made = Create(width, height);
        if (!made.Ok)
            return made;

        var picture = made.Value;
        var backend = (Backend)Imaging.CurrentBackend;
        if (!backend.WritePixels(picture._handle, width, height, &pixels[0u]))
            return Fail(ImageError.OutOfMemory);
        return Ok(picture);
    }

    // ------------------------------------------------------------ what it is

    public int Width => _wide;
    public int Height => _high;

    /// Whether the picture is still open. False only after a destructor has
    /// run, which a program cannot observe on an image it still holds.
    public bool IsOpen => _handle != null;

    // ---------------------------------------------------------------- pixels

    /// The colour at a point, or fully transparent for a point outside.
    ///
    /// Answering rather than failing, because the common caller is a loop over
    /// a neighbourhood and a test at every edge is what that loop would
    /// otherwise be made of.
    public Rgba GetPixel(int x, int y)
    {
        if (!ContainsPoint(x, y))
            return Rgba.Transparent;
        var backend = Imaging.CurrentBackend;
        if (backend == null)
            return Rgba.Transparent;
        return Rgba.FromPacked(((Backend)backend).GetPixel(_handle, x, y));
    }

    /// Writes one pixel, replacing whatever was there rather than blending.
    public void SetPixel(int x, int y, Rgba colour)
    {
        if (!ContainsPoint(x, y))
            return;
        var backend = Imaging.CurrentBackend;
        if (backend != null)
            ((Backend)backend).SetPixel(_handle, x, y, colour.Packed);
    }

    /// How many bytes one row of `CopyPixels` occupies: four per pixel, with no
    /// padding between rows.
    public nuint Stride => (nuint)_wide * 4u;

    /// How many bytes `CopyPixels` writes.
    public nuint PixelByteLength => Stride * (nuint)_high;

    /// Every pixel, as four bytes each in the order **blue, green, red,
    /// alpha**, rows top to bottom with no padding.
    ///
    /// That order rather than red-first because it is what both a Windows DIB
    /// and this module's own `Rgba.Packed` already are: `Packed` is
    /// `0xAARRGGBB`, and its bytes on every machine this compiles for are B, G,
    /// R, A. A reader wanting the other order swaps two bytes per pixel and
    /// knows it is doing so; making this the packed order would have every
    /// reader convert instead.
    ///
    /// The alpha is **straight, not premultiplied**. Premultiplying is what a
    /// particular compositor wants rather than what the picture is, so it
    /// belongs to whoever is about to composite.
    ///
    /// False when the picture is closed, when there is no backend, when `into`
    /// is shorter than `PixelByteLength`, or when the backend refused.
    ///
    /// @see Image.ToBgra
    public bool CopyPixels(byte[] into)
    {
        if (_handle == null || into.Length < PixelByteLength)
            return false;

        var backend = Imaging.CurrentBackend;
        if (backend == null)
            return false;

        return ((Backend)backend).CopyPixels(_handle, _wide, _high, &into[0u]);
    }

    /// The same bytes in an array of the right size, or an empty one for the
    /// failures `CopyPixels` answers false for.
    ///
    /// Empty rather than null for the reason `Encode` gives: an array is a value
    /// here and is never null, and a picture with no pixels is not something
    /// either backend produces.
    ///
    /// @see Image.CopyPixels
    public byte[] ToBgra()
    {
        var pixels = new byte[PixelByteLength];
        if (!CopyPixels(pixels))
            return new byte[0u];
        return pixels;
    }

    bool ContainsPoint(int x, int y)
    {
        return _handle != null && x >= 0 && y >= 0 && x < _wide && y < _high;
    }

    // --------------------------------------------------------------- drawing
    //
    // Every one of these is clipped by the backend, takes the colour it draws
    // with rather than reading a current one, and answers nothing. The first is
    // the reason there is no bounds checking here; the second is the rule
    // `Forms.Drawing` states at length and this one inherits.

    /// Fills the whole picture with one colour.
    public void Clear(Rgba colour)
    {
        var backend = Imaging.CurrentBackend;
        if (backend != null && _handle != null)
            ((Backend)backend).ClearImage(_handle, colour.Packed);
    }

    public void DrawLine(Rgba colour, int x1, int y1, int x2, int y2, int thickness = 1)
    {
        var backend = Imaging.CurrentBackend;
        if (backend == null || _handle == null)
            return;
        ((Backend)backend).DrawLine(_handle, x1, y1, x2, y2, colour.Packed, thickness);
    }

    public void DrawRectangle(Rgba colour, int x, int y, int width, int height,
                              int thickness = 1)
    {
        RenderShape(false, colour, x, y, width, height, thickness, false);
    }

    public void FillRectangle(Rgba colour, int x, int y, int width, int height)
    {
        RenderShape(false, colour, x, y, width, height, 1, true);
    }

    /// An ellipse inside the rectangle given, which is how every other API here
    /// and in `Forms.Drawing` spells one -- libgd's centre-and-size form is
    /// converted by the backend.
    public void DrawEllipse(Rgba colour, int x, int y, int width, int height,
                            int thickness = 1)
    {
        RenderShape(true, colour, x, y, width, height, thickness, false);
    }

    public void FillEllipse(Rgba colour, int x, int y, int width, int height)
    {
        RenderShape(true, colour, x, y, width, height, 1, true);
    }

    void RenderShape(bool ellipse, Rgba colour, int x, int y, int width, int height,
               int thickness, bool filled)
    {
        if (width <= 0 || height <= 0 || _handle == null)
            return;
        var backend = Imaging.CurrentBackend;
        if (backend == null)
            return;
        ((Backend)backend).DrawShape(_handle, ellipse, x, y, width, height,
                                 colour.Packed, thickness, filled);
    }

    /// A closed shape, from x and y in one flat array: `[x0, y0, x1, y1, ...]`.
    ///
    /// **A flat array rather than a `Point[]`**, and that is a deliberate
    /// absence. `Forms.Drawing` declares `Point`, `Size` and `Rectangle`, and a
    /// program that loaded a PNG to put it on a form would have to qualify
    /// every mention of whichever one it meant. Neither library should be the
    /// one that makes the other awkward to import, so this one declares no
    /// geometry at all.
    public void DrawPolygon(Rgba colour, int[] points, int thickness = 1)
    {
        RenderPolygon(colour, points, thickness, false);
    }

    public void FillPolygon(Rgba colour, int[] points)
    {
        RenderPolygon(colour, points, 1, true);
    }

    void RenderPolygon(Rgba colour, int[] points, int thickness, bool filled)
    {
        if (points.Length < 6u || points.Length % 2u != 0u || _handle == null)
            return;
        var backend = Imaging.CurrentBackend;
        if (backend == null)
            return;
        ((Backend)backend).DrawPolygon(_handle, points, colour.Packed, thickness, filled);
    }

    /// Draws another picture on this one, at its own size.
    ///
    /// @see Image.DrawImageScaled
    public void DrawImage(Image source, int x, int y)
    {
        DrawImageScaled(source, x, y, source.Width, source.Height,
                   0, 0, source.Width, source.Height);
    }

    /// Draws part of another picture into a rectangle of this one, scaling to
    /// fit. What a thumbnail and a sprite sheet are both made of.
    public void DrawImageScaled(Image source, int x, int y, int width, int height,
                           int sourceX, int sourceY, int sourceWidth, int sourceHeight)
    {
        if (_handle == null || source._handle == null)
            return;
        if (width <= 0 || height <= 0 || sourceWidth <= 0 || sourceHeight <= 0)
            return;

        var backend = Imaging.CurrentBackend;
        if (backend == null)
            return;
        ((Backend)backend).BlitImage(_handle, source._handle, x, y, width, height,
                                sourceX, sourceY, sourceWidth, sourceHeight);
    }

    /// A copy at another size, resampled.
    ///
    /// @failure ImageError.NoBackend    there is no imaging library on this
    ///                                  machine
    /// @failure ImageError.OutOfMemory  the backend would not make a picture
    ///                                  that big
    /// @failure ImageError.Invalid      a width or a height that is not
    ///                                  positive
    /// @see Image.DrawImageScaled
    public Result<Image, ImageError> Resize(int width, int height)
    {
        var made = Create(width, height);
        if (!made.Ok)
            return made;

        made.Value.DrawImageScaled(this, 0, 0, width, height, 0, 0, _wide, _high);
        return made;
    }

    // ---------------------------------------------------------------- saving

    /// The encoded bytes, in the format asked for.
    ///
    /// `quality` is 0 to 100 and reaches libgd's JPEG encoder; -1 is that
    /// encoder's own default. GDI+ ignores it -- setting it there needs an
    /// `EncoderParameters` laid out by hand for the one format that reads one,
    /// and its default of 75 is the same number libgd uses.
    ///
    /// @failure ImageError.NoBackend    there is no imaging library on this
    ///                                  machine
    /// @failure ImageError.Unsupported  the backend cannot write that format
    ///                                  -- a BMP on a libgd built without one
    ///                                  -- or the encode failed, which it
    ///                                  reports no other way
    /// @see Image.FromBytes
    public Result<byte[], ImageError> Encode(ImageFormat format, int quality = -1)
    {
        if (_handle == null)
            return Fail(ImageError.Invalid);

        var backend = Imaging.CurrentBackend;
        if (backend == null)
            return Fail(ImageError.NoBackend);

        var data = ((Backend)backend).EncodeImage(_handle, format, quality);
        if (data.Length == 0u)
            return Fail(ImageError.Unsupported);
        return Ok(data);
    }

    /// Encodes and writes to a file. `ImageError.None` when it worked.
    ///
    /// @failure ImageError.NoBackend    there is no imaging library on this
    ///                                  machine
    /// @failure ImageError.Unsupported  the backend cannot write that format,
    ///                                  or the encode failed
    /// @failure ImageError.WriteFailed  the picture encoded and the file would
    ///                                  not be written
    /// @see Image.FromFile
    public ImageError Save(String path, ImageFormat format, int quality = -1)
    {
        var data = Encode(format, quality);
        if (!data.Ok)
            return data.Error;

        var written = WriteAllBytes(path, data.Value);
        return written == IOError.None ? ImageError.None : ImageError.WriteFailed;
    }
}
