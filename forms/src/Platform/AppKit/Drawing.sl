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

// Drawing on AppKit: CoreGraphics for the shapes, AppKit's string drawing for
// the text, and a `CGImage` for a picture.
//
// **The geometry is the cairo backend's**, which is the one this most nearly
// is: a CoreGraphics stroke is centred on its path as a cairo one is, so the
// same half-pixel offset puts a one-pixel line on one pixel, and a rectangle's
// outline runs through the centres of its edge pixels as GDI draws it.
//
// **A size in points is scaled as GTK scales one**, by 96 over 72, so a form
// laid out for 9-point text on Windows has room for it here too.
module Forms.Platform.AppKit;

import Standard.Collections;
import Standard.Text;
import Forms;
import Forms.Drawing;
import Forms.Platform;
#if MACOS && !FORMS_GTK
import Standard.ObjC;
import MacOS.System;
import MacOS.CoreFoundation;
import MacOS.CoreGraphics;
import MacOS.Foundation;
import MacOS.AppKit;

// ==================================================================== font

/// The size AppKit draws a font of `points` at. See the file's header.
public double ScaleFontSize(int points) => (double)points * 96.0 / 72.0;

/// A font, as AppKit holds one: an `NSFont` with the weight and slant asked
/// for, or the system's font when no family of that name is installed.
public class AppKitFontBackend : IFontBackend
{
    public NSFont Font { get; }

    public AppKitFontBackend(Forms.Drawing.Font font)
    {
        double size = ScaleFontSize(font.Size);
        var named = NSFont.FontWithNameSize(ToNSString(font.Family), size);
        NSFont made = named == null ? NSFont.SystemFontOfSize(size) : (NSFont)named;

        var manager = NSFontManager.SharedFontManager;
        if (font.Bold)
            made = manager.ConvertFontToHaveTrait(made, NSFontTraitMask.BoldFontMask);
        if (font.Italic)
            made = manager.ConvertFontToHaveTrait(made, NSFontTraitMask.ItalicFontMask);

        // A fixed-pitch face is sized so a cell is a whole number of pixels,
        // as GDI's and FreeType's hinting leave one. Text laid out by cell
        // otherwise drifts by the fraction at every column.
        if (made.FixedPitch)
        {
            double advance = made.MaximumAdvancement.width;
            double whole = (double)RoundToInt(advance);
            if (advance > 0.0 && whole >= 1.0 && whole != advance)
                made = made.FontWithSize(made.PointSize * whole / advance);
        }
        Font = made;
    }

    public nuint Handle => (nuint)(byte*)Font;
}

NSFont FindNSFont(Forms.Drawing.Font font) => ((AppKitFontBackend)font.Resource).Font;

/// What AppKit's string drawing takes: the font and the colour.
NSMutableDictionary CreateTextAttributes(Forms.Drawing.Font font, Color color)
{
    var attributes = NSMutableDictionary.Dictionary();
    attributes.SetObjectForKey(FindNSFont(font), NSFontAttributeName);
    attributes.SetObjectForKey(ToNSColor(color), NSForegroundColorAttributeName);
    return attributes;
}

// ================================================================ pictures

/// A picture, which AppKit draws as a `CGImage`.
public class AppKitBitmapBackend : IBitmapBackend
{
    CGImageRef _image;
    bool _hasAlpha;

    public AppKitBitmapBackend(CGImageRef image, bool hasAlpha)
    {
        _image = image;
        _hasAlpha = hasAlpha;
    }

    public CGImageRef Image => _image;
    public int Width => (int)CGImageGetWidth(_image);
    public int Height => (int)CGImageGetHeight(_image);
    public nuint Handle => (nuint)(byte*)_image;
    public bool HasAlpha => _hasAlpha;
}

/// A picture from pixels in `CreateBitmap`'s order: blue, green, red and
/// straight alpha, which in a little-endian word is alpha first.
public Result<IBitmapBackend, String> CreatePixelBitmap(int width, int height, byte[] pixels)
{
    if (width <= 0 || height <= 0 || pixels.Length < (nuint)(width * height * 4))
        return Fail("the pixels do not fill a picture of that size");

    var data = CFDataCreate(null, &pixels[0u], (CFIndex)(width * height * 4));
    var provider = CGDataProviderCreateWithCFData(data);
    var space = CGColorSpaceCreateDeviceRGB();
    var info = (CGBitmapInfo)((uint)CGBitmapInfo.ByteOrder32Little | (uint)CGImageAlphaInfo.First);
    var image = CGImageCreate((nuint)width, (nuint)height, 8u, 32u, (nuint)(width * 4), space, info,
                              provider, null, true, CGColorRenderingIntent.Default);
    if (image == null)
        return Fail("CoreGraphics would not make that picture");
    return Ok(new AppKitBitmapBackend((CGImageRef)image, true));
}

/// A picture AppKit decodes itself: a file, or the bytes of one.
public Result<IBitmapBackend, String> CreateDecodedBitmap(NSImage? decoded, String what)
{
    if (decoded == null)
        return Fail("could not read " + what);
    var image = ((NSImage)decoded).CGImageForProposedRectContextHints(null, null, null);
    if (image == null)
        return Fail("could not read " + what);
    return Ok(new AppKitBitmapBackend((CGImageRef)image, true));
}

/// Same-sized pictures, indexed by number.
public class AppKitImageListBackend : IImageListBackend
{
    List<IBitmapBackend> _pictures;
    FSize _imageSize;

    public AppKitImageListBackend(FSize imageSize)
    {
        _pictures = new List<IBitmapBackend>();
        _imageSize = imageSize;
    }

    public int Add(IBitmapBackend picture)
    {
        _pictures.Add(picture);
        return (int)_pictures.Count - 1;
    }

    public int Count => (int)_pictures.Count;
    public FSize ImageSize => _imageSize;
    public nuint Handle => 0u;

    /// One picture, or null for an index nothing was added at.
    public IBitmapBackend? GetPicture(int index)
    {
        if (index < 0 || (nuint)index >= _pictures.Count)
            return null;
        return _pictures[(nuint)index];
    }
}

// ================================================================ graphics

/// A CoreGraphics context behind `IGraphicsBackend`. Borrowed: it is AppKit's
/// for the length of one `drawRect:`, already clipped to what needs drawing.
public class AppKitGraphicsBackend : IGraphicsBackend
{
    CGContextRef? _context;
    int _depth;

    public AppKitGraphicsBackend(CGContextRef? context, NSView drawn)
    {
        _context = context;
        _depth = 0;
    }

    // ------------------------------------------------------------- layers

    public int PushLayer(FRect bounds)
    {
        CGContextSaveGState(_context);
        CGContextClipToRect(_context, ToNSRect(bounds));
        CGContextTranslateCTM(_context, (double)bounds.X, (double)bounds.Y);
        _depth++;
        return _depth;
    }

    public void PopLayer(int token)
    {
        if (token != _depth)
            return;
        CGContextRestoreGState(_context);
        _depth--;
    }

    public FRect ClipBounds => FromNSRect(CGContextGetClipBoundingBox(_context));

    // -------------------------------------------------------------- paint

    void SetFill(Color color) =>
        CGContextSetRGBFillColor(_context, (double)(int)color.R / 255.0, (double)(int)color.G / 255.0,
                                 (double)(int)color.B / 255.0, (double)(int)color.A / 255.0);

    /// Everything a pen decides, and the half pixel an odd width needs to land
    /// on whole pixels; see the file's header.
    double ApplyPen(Pen pen)
    {
        CGContextSetRGBStrokeColor(_context, (double)(int)pen.Color.R / 255.0, (double)(int)pen.Color.G / 255.0,
                                   (double)(int)pen.Color.B / 255.0, (double)(int)pen.Color.A / 255.0);
        CGContextSetLineWidth(_context, (double)pen.Width);

        // GDI's lengths for the same three styles, as the cairo backend uses.
        if (pen.Style == PenStyle.Dash)
        {
            double[2] pattern = [6.0, 3.0];
            CGContextSetLineDash(_context, 0.0, &pattern[0u], 2u);
        }
        else if (pen.Style == PenStyle.Dot)
        {
            double[2] pattern = [1.0, 3.0];
            CGContextSetLineDash(_context, 0.0, &pattern[0u], 2u);
        }
        else if (pen.Style == PenStyle.DashDot)
        {
            double[4] pattern = [6.0, 3.0, 1.0, 3.0];
            CGContextSetLineDash(_context, 0.0, &pattern[0u], 4u);
        }
        else
        {
            CGContextSetLineDash(_context, 0.0, null, 0u);
        }
        return (pen.Width % 2) == 1 ? 0.5 : 0.0;
    }

    public void Clear(Color color)
    {
        SetFill(color);
        CGContextFillRect(_context, CGContextGetClipBoundingBox(_context));
    }

    public void DrawLine(Pen pen, int x1, int y1, int x2, int y2)
    {
        if (pen.Style == PenStyle.None)
            return;
        double half = ApplyPen(pen);
        CGContextBeginPath(_context);
        CGContextMoveToPoint(_context, (double)x1 + half, (double)y1 + half);
        CGContextAddLineToPoint(_context, (double)x2 + half, (double)y2 + half);
        CGContextStrokePath(_context);
    }

    /// Inside the rectangle, as GDI draws it.
    public void DrawRectangle(Pen pen, FRect bounds)
    {
        if (pen.Style == PenStyle.None || bounds.Width <= 0 || bounds.Height <= 0)
            return;
        double half = ApplyPen(pen);
        CGContextBeginPath(_context);
        CGContextAddRect(_context, MakeNSRect((double)bounds.X + half, (double)bounds.Y + half,
                                              (double)(bounds.Width - 1), (double)(bounds.Height - 1)));
        CGContextStrokePath(_context);
    }

    public void FillRectangle(Brush brush, FRect bounds)
    {
        if (!brush.IsGradient)
        {
            SetFill(brush.Color);
            CGContextFillRect(_context, ToNSRect(bounds));
            return;
        }

        double[8] components = [
            (double)(int)brush.Color.R / 255.0, (double)(int)brush.Color.G / 255.0,
            (double)(int)brush.Color.B / 255.0, (double)(int)brush.Color.A / 255.0,
            (double)(int)brush.EndColor.R / 255.0, (double)(int)brush.EndColor.G / 255.0,
            (double)(int)brush.EndColor.B / 255.0, (double)(int)brush.EndColor.A / 255.0];
        double[2] stops = [0.0, 1.0];
        var space = CGColorSpaceCreateDeviceRGB();
        var ramp = CGGradientCreateWithColorComponents(space, &components[0u], &stops[0u], 2u);

        CGPoint from;
        from.x = (double)bounds.X;
        from.y = (double)bounds.Y;
        CGPoint to = from;
        if (brush.Style == BrushStyle.HorizontalGradient)
            to.x = (double)(bounds.X + bounds.Width);
        else
            to.y = (double)(bounds.Y + bounds.Height);

        CGContextSaveGState(_context);
        CGContextClipToRect(_context, ToNSRect(bounds));
        CGContextDrawLinearGradient(_context, ramp, from, to, (CGGradientDrawingOptions)0u);
        CGContextRestoreGState(_context);
    }

    public void DrawEllipse(Pen pen, FRect bounds)
    {
        if (pen.Style == PenStyle.None || bounds.Width <= 0 || bounds.Height <= 0)
            return;
        ApplyPen(pen);
        CGContextStrokeEllipseInRect(_context, ToNSRect(bounds));
    }

    public void FillEllipse(Brush brush, FRect bounds)
    {
        if (bounds.Width <= 0 || bounds.Height <= 0)
            return;
        SetFill(brush.Color);
        CGContextFillEllipseInRect(_context, ToNSRect(bounds));
    }

    void TracePath(FPoint[] points, double half, bool close)
    {
        CGContextBeginPath(_context);
        if (points.Length == 0u)
            return;
        CGContextMoveToPoint(_context, (double)points[0u].X + half, (double)points[0u].Y + half);
        for (nuint i = 1u; i < points.Length; i++)
            CGContextAddLineToPoint(_context, (double)points[i].X + half, (double)points[i].Y + half);
        if (close)
            CGContextClosePath(_context);
    }

    public void DrawPolygon(Pen pen, FPoint[] points)
    {
        if (pen.Style == PenStyle.None)
            return;
        double half = ApplyPen(pen);
        TracePath(points, half, true);
        CGContextStrokePath(_context);
    }

    public void FillPolygon(Brush brush, FPoint[] points)
    {
        SetFill(brush.Color);
        TracePath(points, 0.0, true);
        CGContextFillPath(_context);
    }

    public void DrawPolyline(Pen pen, FPoint[] points)
    {
        if (pen.Style == PenStyle.None)
            return;
        double half = ApplyPen(pen);
        TracePath(points, half, false);
        CGContextStrokePath(_context);
    }

    // --------------------------------------------------------------- text

    /// From the top-left, as every API here means a text position. The view
    /// is flipped, so AppKit's string drawing starts there too.
    public void DrawString(String text, Forms.Drawing.Font font, Color color, int x, int y)
    {
        if (text.IsEmpty)
            return;
        CGPoint at;
        at.x = (double)x;
        at.y = (double)y;
        ToNSString(text).DrawAtPointWithAttributes(at, CreateTextAttributes(font, color));
        DrawTextDecorations(text, font, color, x, y);
    }

    public void DrawStringIn(String text, Forms.Drawing.Font font, Color color, FRect bounds, TextFormat format)
    {
        if (text.IsEmpty)
            return;
        var extent = MeasureString(text, font);

        int x = bounds.X;
        if (format.Horizontal == HorizontalAlignment.Center)
            x = bounds.X + (bounds.Width - extent.Width) / 2;
        else if (format.Horizontal == HorizontalAlignment.Right)
            x = bounds.X + bounds.Width - extent.Width;

        int y = bounds.Y;
        if (format.Vertical == VerticalAlignment.Middle)
            y = bounds.Y + (bounds.Height - extent.Height) / 2;
        else if (format.Vertical == VerticalAlignment.Bottom)
            y = bounds.Y + bounds.Height - extent.Height;

        // Clipped to the rectangle, so a caption longer than its box stops at
        // the edge rather than running over whatever is beside it.
        CGContextSaveGState(_context);
        CGContextClipToRect(_context, ToNSRect(bounds));
        DrawString(text, font, color, x, y);
        CGContextRestoreGState(_context);
    }

    /// Underline and strikeout, drawn as lines where every toolkit puts them:
    /// just under the baseline, and a third of the ascent above it.
    void DrawTextDecorations(String text, Forms.Drawing.Font font, Color color, int x, int y)
    {
        if (!font.Underline && !font.Strikeout)
            return;
        var shown = FindNSFont(font);
        double baseline = (double)y + shown.Ascender;
        int width = MeasureString(text, font).Width;
        var line = new Pen(color);
        if (font.Underline)
            DrawLine(line, x, FloorToInt(baseline + 1.0), x + width, FloorToInt(baseline + 1.0));
        if (font.Strikeout)
        {
            int at = FloorToInt(baseline - shown.Ascender / 3.0);
            DrawLine(line, x, at, x + width, at);
        }
    }

    /// The advance width and the font's line height, not the ink's, so a row
    /// of labels lines up whatever letters they hold.
    public FSize MeasureString(String text, Forms.Drawing.Font font)
    {
        var shown = FindNSFont(font);
        int height = (int)(shown.Ascender - shown.Descender + shown.Leading + 0.999);
        if (text.IsEmpty)
            return CreateSize(0, height);
        var size = ToNSString(text).SizeWithAttributes(CreateTextAttributes(font, Colors.Black));
        return CreateSize((int)(size.width + 0.999), height);
    }

    // ------------------------------------------------------------ pictures

    /// Drawn the right way up in a flipped view: CoreGraphics puts an image's
    /// first row at the bottom of the rectangle, so the rectangle is flipped
    /// back for the length of the draw.
    void DrawImage(IBitmapBackend picture, FRect into)
    {
        CGContextSaveGState(_context);
        CGContextTranslateCTM(_context, (double)into.X, (double)(into.Y + into.Height));
        CGContextScaleCTM(_context, 1.0, -1.0);
        CGContextDrawImage(_context, MakeNSRect(0.0, 0.0, (double)into.Width, (double)into.Height),
                           ((AppKitBitmapBackend)picture).Image);
        CGContextRestoreGState(_context);
    }

    public void DrawBitmap(IBitmapBackend picture, FPoint at) =>
        DrawImage(picture, CreateRectangle(at.X, at.Y, picture.Width, picture.Height));

    public void DrawBitmapIn(IBitmapBackend picture, FRect into)
    {
        if (into.Width <= 0 || into.Height <= 0)
            return;
        DrawImage(picture, into);
    }

    public void DrawBitmapFaded(IBitmapBackend picture, FPoint at, int opacity)
    {
        CGContextSaveGState(_context);
        CGContextSetAlpha(_context, (double)opacity / 100.0);
        DrawImage(picture, CreateRectangle(at.X, at.Y, picture.Width, picture.Height));
        CGContextRestoreGState(_context);
    }
}

#endif
