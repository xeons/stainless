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

// The clipboard on AppKit: the general pasteboard.
//
// **One copy is several pasteboard items.** A pasteboard holds one file URL
// to an item, so a copy of three files is three items; the text, the HTML,
// the picture and the program's own formats go on the first.
//
// **A picture travels as PNG** from a bitmap with straight alpha, so a pixel
// half there comes back exactly as it went: a premultiplied one would round it.
//
// **Nothing reports a change.** AppKit counts them and says so to nobody, so
// a watcher polls the count, as the LCL's Cocoa widgetset does.
module Forms.Platform.AppKit;

import Standard.Collections;
import Standard.Text;
import Forms.Drawing;
import Forms.Platform;
#if MACOS && FORMS_APPKIT
import Standard.ObjC;
import MacOS.System;
import MacOS.CoreFoundation;
import MacOS.CoreGraphics;
import MacOS.Foundation;
import MacOS.AppKit;
import MacOS.UniformTypeIdentifiers;

NSPasteboard FindPasteboard() => NSPasteboard.GeneralPasteboard;

/// A `file:` URL for `path` with its own bytes percent-encoded.
///
/// **Not `fileURLWithPath:`, which decomposes the name** as the file system
/// stores it, so `naïve` would come back a byte longer than it went. APFS
/// treats the two forms as one name, so another program finds the file
/// either way, and this program gets back the string it gave.
String FormatFileUrl(String path)
{
    var built = new StringBuilder();
    built.Append("file://");
    for (nuint i = 0u; i < path.ByteLength(); i++)
    {
        byte c = path.GetByteAt(i);
        bool plain = (c >= (byte)'a' && c <= (byte)'z') || (c >= (byte)'A' && c <= (byte)'Z')
                     || (c >= (byte)'0' && c <= (byte)'9') || c == (byte)'-' || c == (byte)'.'
                     || c == (byte)'_' || c == (byte)'~' || c == (byte)'/';
        if (plain)
        {
            built.Append(path.Substring(i, 1u));
            continue;
        }
        built.Append("%");
        built.Append(FormatHexDigit((int)c >> 4));
        built.Append(FormatHexDigit((int)c & 15));
    }
    return built.ToText();
}

/// One hexadecimal digit, upper case.
String FormatHexDigit(int digit) => "0123456789ABCDEF".Substring((nuint)digit, 1u);

/// The pasteboard type a format of the program's own is offered under, which
/// AppKit requires to be a type identifier.
///
/// A MIME type -- `application/x-stainless-shapes` -- becomes the identifier
/// AppKit makes for it, which it maps back from; a name that is already an
/// identifier is used as it is; anything else is made one under `org.stainless`.
NSString FindPasteboardType(String name)
{
    if (name.Contains("/") && UTType.TypeWithMIMEType(ToNSString(name)) is UTType made)
        return made.Identifier;
    bool identifier = name != "";
    for (nuint i = 0u; i < name.ByteLength() && identifier; i++)
    {
        byte c = name.GetByteAt(i);
        identifier = (c >= (byte)'a' && c <= (byte)'z') || (c >= (byte)'A' && c <= (byte)'Z')
                     || (c >= (byte)'0' && c <= (byte)'9') || c == (byte)'-' || c == (byte)'.';
    }
    if (identifier)
        return ToNSString(name);

    var built = new StringBuilder();
    built.Append("org.stainless.format.");
    for (nuint i = 0u; i < name.ByteLength(); i++)
    {
        byte c = name.GetByteAt(i);
        bool kept = (c >= (byte)'a' && c <= (byte)'z') || (c >= (byte)'A' && c <= (byte)'Z')
                    || (c >= (byte)'0' && c <= (byte)'9');
        built.Append(kept ? name.Substring(i, 1u) : "-");
    }
    return ToNSString(built.ToText());
}

/// The name a program would know a pasteboard type by: the MIME type of one
/// AppKit made for a MIME type, and otherwise the identifier.
String DescribePasteboardType(NSString type)
{
    var named = FromNSString(type);
    if (named.StartsWith("dyn.") && UTType.TypeWithIdentifier(type) is UTType made && made.PreferredMIMEType is NSString mime)
        return FromNSString(mime);
    return named;
}

/// An `NSData` holding a copy of `bytes`.
NSData CreateData(byte[] bytes)
{
    if (bytes.Length == 0u)
        return NSData.Data();
    return NSData.DataWithBytesLength(&bytes[0u], bytes.Length);
}

/// A copy of what an `NSData` holds.
byte[] ReadData(NSData? data)
{
    if (data == null)
        return new byte[0u];
    var held = (NSData)data;
    nuint length = held.Length;
    var bytes = new byte[length];
    if (length > 0u)
        held.GetBytesLength(&bytes[0u], length);
    return bytes;
}

/// A picture's PNG bytes, from pixels in the seam's order.
NSData? EncodeClipboardImage(ClipboardImage image)
{
    var rep = NSBitmapImageRep.Alloc().InitWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBitmapFormatBytesPerRowBitsPerPixel(
        null, (NSInteger)image.Width, (NSInteger)image.Height, (NSInteger)8, (NSInteger)4, true, false,
        NSDeviceRGBColorSpace!, NSBitmapFormat.AlphaNonpremultiplied, (NSInteger)(image.Width * 4), (NSInteger)32);
    if (rep == null)
        return null;
    var bitmap = (NSBitmapImageRep)rep;
    byte* to = bitmap.BitmapData;
    nuint stride = (nuint)bitmap.BytesPerRow;
    var from = image.Pixels;
    for (nuint y = 0u; y < (nuint)image.Height; y++)
    {
        for (nuint x = 0u; x < (nuint)image.Width; x++)
        {
            nuint source = (y * (nuint)image.Width + x) * 4u;
            nuint target = y * stride + x * 4u;
            to[target] = from[source + 2u];
            to[target + 1u] = from[source + 1u];
            to[target + 2u] = from[source];
            to[target + 3u] = from[source + 3u];
        }
    }
    return bitmap.RepresentationUsingTypeProperties(NSBitmapImageFileType.PNG, NSDictionary.Dictionary());
}

/// A picture from encoded bytes, in the seam's order, or null.
///
/// A bitmap in any other layout is drawn into one of eight-bit samples with
/// straight alpha first, which is the one this reads.
ClipboardImage? DecodeClipboardImage(NSData data)
{
    var decoded = NSBitmapImageRep.ImageRepWithData(data);
    if (decoded == null)
        return null;
    var rep = (NSBitmapImageRep)decoded;
    int width = (int)rep.PixelsWide;
    int height = (int)rep.PixelsHigh;
    if (width <= 0 || height <= 0)
        return null;

    bool plain = rep.BitsPerSample == (NSInteger)8 && rep.SamplesPerPixel == (NSInteger)4
                 && !rep.Planar && rep.BitmapFormat == NSBitmapFormat.AlphaNonpremultiplied;
    if (!plain)
    {
        var redrawn = NSBitmapImageRep.Alloc().InitWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBitmapFormatBytesPerRowBitsPerPixel(
            null, (NSInteger)width, (NSInteger)height, (NSInteger)8, (NSInteger)4, true, false,
            NSDeviceRGBColorSpace!, NSBitmapFormat.AlphaNonpremultiplied, (NSInteger)(width * 4), (NSInteger)32);
        var context = redrawn == null ? null : NSGraphicsContext.GraphicsContextWithBitmapImageRep((NSBitmapImageRep)redrawn);
        if (redrawn == null || context == null)
            return null;
        NSGraphicsContext.SaveGraphicsState();
        NSGraphicsContext.CurrentContext = context;
        rep.DrawInRect(MakeNSRect(0.0, 0.0, (double)width, (double)height));
        NSGraphicsContext.RestoreGraphicsState();
        rep = (NSBitmapImageRep)redrawn;
    }

    byte* from = rep.BitmapData;
    nuint stride = (nuint)rep.BytesPerRow;
    var pixels = new byte[(nuint)width * (nuint)height * 4u];
    for (nuint y = 0u; y < (nuint)height; y++)
    {
        for (nuint x = 0u; x < (nuint)width; x++)
        {
            nuint source = y * stride + x * 4u;
            nuint target = (y * (nuint)width + x) * 4u;
            pixels[target] = from[source + 2u];
            pixels[target + 1u] = from[source + 1u];
            pixels[target + 2u] = from[source];
            pixels[target + 3u] = from[source + 3u];
        }
    }
    return new ClipboardImage(width, height, pixels);
}

/// Replaces what the pasteboard holds with everything `content` offers; empty
/// content empties it.
void WriteClipboard(ClipboardContent content)
{
    var board = FindPasteboard();
    board.ClearContents();
    if (content.IsEmpty)
        return;

    var items = NSMutableArray.Array();
    var first = NSPasteboardItem.Alloc().Init()!;
    var text = content.Text;
    if (text != null)
        first.SetStringForType(ToNSString((String)text), NSPasteboardTypeString!);
    var html = content.Html;
    if (html != null)
        first.SetStringForType(ToNSString((String)html), NSPasteboardTypeHTML!);
    var image = content.Image;
    if (image != null && EncodeClipboardImage((ClipboardImage)image) is NSData png)
        first.SetDataForType(png, NSPasteboardTypePNG!);
    foreach (var entry in content.Custom)
        first.SetDataForType(CreateData(entry.Data), FindPasteboardType(entry.Name));

    for (nuint i = 0u; i < content.Files.Length; i++)
    {
        var holder = i == 0u ? first : NSPasteboardItem.Alloc().Init()!;
        holder.SetStringForType(ToNSString(FormatFileUrl(content.Files[i])), NSPasteboardTypeFileURL!);
        if (i > 0u)
            items.AddObject(holder);
    }
    items.InsertObjectAtIndex(first, 0u);
    board.WriteObjects(items);
}

/// Whether the pasteboard offers `type`.
bool OffersPasteboardType(NSPasteboardType type) =>
    FindPasteboard().AvailableTypeFromArray(NSArray.ArrayWithObject(type)) != null;

String ReadClipboardString(NSPasteboardType type)
{
    var found = FindPasteboard().StringForType(type);
    return found == null ? "" : FromNSString((NSString)found);
}

ClipboardImage? ReadClipboardImage()
{
    var board = FindPasteboard();
    var data = board.DataForType(NSPasteboardTypePNG!);
    if (data == null)
        data = board.DataForType(NSPasteboardTypeTIFF!);
    return data == null ? null : DecodeClipboardImage((NSData)data);
}

/// The local paths of the file URLs on offer, one to an item.
String[] ReadClipboardFiles()
{
    var found = new List<String>();
    var items = FindPasteboard().PasteboardItems;
    if (items == null)
        return found.ToArray();
    var held = (NSArray)items;
    for (nuint i = 0u; i < held.Count; i++)
    {
        var item = (NSPasteboardItem)held.ObjectAtIndex(i);
        var written = item.StringForType(NSPasteboardTypeFileURL!);
        if (written == null)
            continue;
        var url = NSURL.URLWithString((NSString)written);
        var path = url == null ? null : ((NSURL)url).Path;
        if (path != null)
            found.Add(FromNSString((NSString)path));
    }
    return found.ToArray();
}

String[] ReadClipboardTypes()
{
    var found = new List<String>();
    var types = FindPasteboard().Types;
    if (types == null)
        return found.ToArray();
    var held = (NSArray)types;
    for (nuint i = 0u; i < held.Count; i++)
        found.Add(DescribePasteboardType((NSString)held.ObjectAtIndex(i)));
    return found.ToArray();
}

/// Reports a change of the pasteboard's count, which polling finds.
public class AppKitClipboardWatchPeer : IClipboardWatchPeer
{
    weak IClipboardNotify? _owner;
    NSTimer? _timer;
    NSInteger _seen;

    public AppKitClipboardWatchPeer(IClipboardNotify owner)
    {
        _owner = owner;
        _timer = null;
        _seen = FindPasteboard().ChangeCount;
    }

    ~AppKitClipboardWatchPeer() { Stop(); }

    /// A quarter of a second between looks, in every run loop mode, so a
    /// change made while a menu or a modal window is up is still heard.
    public void Start()
    {
        Stop();
        _seen = FindPasteboard().ChangeCount;
        var relay = new ClipboardWatchRelay(this);
        var timer = NSTimer.TimerWithTimeIntervalRepeatsBlock(0.25, true, (fired) => relay.Look());
        NSRunLoop.MainRunLoop.AddTimerForMode(timer, NSRunLoopCommonModes);
        _timer = timer;
    }

    public void Stop()
    {
        if (_timer is NSTimer timer)
            timer.Invalidate();
        _timer = null;
    }

    public void Look()
    {
        var now = FindPasteboard().ChangeCount;
        if (now == _seen)
            return;
        _seen = now;
        IClipboardNotify? owner = _owner;
        if (owner != null)
            ((IClipboardNotify)owner).OnPlatformClipboardChanged();
    }
}

/// What a watcher's timer holds instead of the watcher, so a running timer
/// does not keep it alive.
class ClipboardWatchRelay
{
    weak AppKitClipboardWatchPeer? _peer;

    public ClipboardWatchRelay(AppKitClipboardWatchPeer peer) => _peer = peer;

    public void Look()
    {
        AppKitClipboardWatchPeer? peer = _peer;
        if (peer != null)
            ((AppKitClipboardWatchPeer)peer).Look();
    }
}

#endif
