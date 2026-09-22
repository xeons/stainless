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

// The clipboard, as Windows keeps it.
//
// **The clipboard is a lock.** One process holds it at a time, and a process
// that opens it and returns without closing it leaves every other program on
// the desktop unable to copy or paste until it exits. So every function here
// that opens it has exactly one `CloseClipboard`, reached on every way out, and
// does its slow work -- encoding a picture, above all -- before opening it.
//
// **Every format is rendered at once**, never on demand. Delayed rendering
// would mean answering `WM_RENDERFORMAT` from a window that may be gone by the
// time another program pastes, and a copy is expected to outlive the program
// that made it.
//
// Pictures go on in three forms: `CF_DIB`, which every program reads;
// `CF_DIBV5`, which says what its fourth byte means; and the registered `PNG`
// format, which is what browsers and image editors read to keep transparency.
// They come off in the reverse order of preference.
module Forms.Platform.Win32;

import Standard.Collections;
import Standard.Convert;
import Standard.Text;
import Forms.Platform;
#if WINDOWS
import Win32;
import Win32.Handles;
import Win32.Kernel32;
import Win32.User32;
import Win32.Shell32;

/// `BI_RGB` and `BI_BITFIELDS`: how a DIB's pixels are laid out.
const uint DibRgb = 0u;
const uint DibBitFields = 3u;

/// `BI_ALPHABITFIELDS`, which Windows CE introduced and a few programs write.
const uint DibAlphaBitFields = 6u;

/// `LCS_sRGB`, the colour space a `BITMAPV5HEADER` says it is in.
const uint ColourSpaceSrgb = 0x73524742u;

/// `LCS_GM_IMAGES`, the rendering intent for a photograph.
const uint IntentImages = 4u;

/// `DROPEFFECT_COPY`: what Explorer should do with pasted files.
const uint DropEffectCopy = 1u;

/// How many times, and how long apart, to try a clipboard another program is
/// holding. A clipboard viewer reading what was just copied holds it for a
/// moment, so a copy that tried once would sometimes silently do nothing.
const int OpenAttempts = 10;
const uint OpenRetryMilliseconds = 10u;

// ============================================================ formats by name

static uint s_htmlFormat = 0u;
static uint s_pngFormat = 0u;
static uint s_dropEffectFormat = 0u;

/// The id Windows gives a format name, or zero.
uint RegisterFormatNamed(String name)
{
    return RegisterClipboardFormatW(name.ToUtf16().ToPointer());
}

/// `"HTML Format"`, which is what every browser and word processor reads.
uint HtmlFormat()
{
    if (s_htmlFormat == 0u)
        s_htmlFormat = RegisterFormatNamed("HTML Format");
    return s_htmlFormat;
}

/// `"PNG"`, the unofficial and universal way to carry transparency.
uint PngFormat()
{
    if (s_pngFormat == 0u)
        s_pngFormat = RegisterFormatNamed("PNG");
    return s_pngFormat;
}

uint DropEffectFormat()
{
    if (s_dropEffectFormat == 0u)
        s_dropEffectFormat = RegisterFormatNamed("Preferred DropEffect");
    return s_dropEffectFormat;
}

/// What a format is called: its registered name, or the constant's name for a
/// predefined one, which has no name of its own to ask for.
String NameOfClipboardFormat(uint format)
{
    switch (format)
    {
        case 1u:    return "CF_TEXT";
        case 2u:    return "CF_BITMAP";
        case 3u:    return "CF_METAFILEPICT";
        case 4u:    return "CF_SYLK";
        case 5u:    return "CF_DIF";
        case 6u:    return "CF_TIFF";
        case 7u:    return "CF_OEMTEXT";
        case 8u:    return "CF_DIB";
        case 9u:    return "CF_PALETTE";
        case 10u:   return "CF_PENDATA";
        case 11u:   return "CF_RIFF";
        case 12u:   return "CF_WAVE";
        case 13u:   return "CF_UNICODETEXT";
        case 14u:   return "CF_ENHMETAFILE";
        case 15u:   return "CF_HDROP";
        case 16u:   return "CF_LOCALE";
        case 17u:   return "CF_DIBV5";
        case 0x80u: return "CF_OWNERDISPLAY";
        case 0x81u: return "CF_DSPTEXT";
        case 0x82u: return "CF_DSPBITMAP";
        case 0x83u: return "CF_DSPMETAFILEPICT";
        case 0x8Eu: return "CF_DSPENHMETAFILE";
    }

    var buffer = new char16[256u];
    int units = GetClipboardFormatNameW(format, &buffer[0u], 256);
    if (units > 0)
        return Text.FromUtf16(&buffer[0u], (nuint)units);
    return "#" + Text.FromInteger((ulong)format);
}

// ======================================================= opening and closing

/// Opens the clipboard for this program, waiting briefly for another to let
/// go of it. The caller MUST call `CloseClipboard` when this answers true.
///
/// Opened on the wake window rather than on no window: after `EmptyClipboard`
/// the opener is the owner, and an owner of null is documented to make
/// `SetClipboardData` fail.
bool OpenClipboardPatiently()
{
    for (int attempt = 0; attempt < OpenAttempts; attempt++)
    {
        if (OpenClipboard(s_wake) != 0)
            return true;
        Sleep(OpenRetryMilliseconds);
    }
    return false;
}

/// Whether a format is on offer. Needs no lock.
bool ClipboardOffers(uint format)
{
    return format != 0u && IsClipboardFormatAvailable(format) != 0;
}

// ============================================================ memory blocks

/// A moveable block holding a copy of `length` bytes, or null.
///
/// Moveable because the clipboard requires it. At least one byte, because a
/// zero-byte `GlobalAlloc` answers a handle to discarded memory that
/// `GlobalLock` refuses.
HGLOBAL BlockHolding(byte* data, nuint length)
{
    HGLOBAL block = GlobalAlloc(GlobalMoveable | GlobalZeroInit, length == 0u ? 1u : length);
    if (block == null)
        return null;

    byte* into = (byte*)GlobalLock(block);
    if (into == null)
    {
        GlobalFree(block);
        return null;
    }
    for (nuint i = 0u; i < length; i++)
        into[i] = data[i];
    GlobalUnlock(block);
    return block;
}

HGLOBAL BlockHoldingBytes(byte[] data)
{
    if (data.Length == 0u)
        return BlockHolding(null, 0u);
    return BlockHolding(&data[0u], data.Length);
}

/// Text as `CF_UNICODETEXT` wants it: UTF-16, with a terminator.
HGLOBAL BlockHoldingUtf16(String text)
{
    var wide = text.ToUtf16();
    nuint units = wide.UnitCount();
    HGLOBAL block = GlobalAlloc(GlobalMoveable | GlobalZeroInit, (units + 1u) * 2u);
    if (block == null)
        return null;

    char16* into = (char16*)GlobalLock(block);
    if (into == null)
    {
        GlobalFree(block);
        return null;
    }
    char16* from = wide.ToPointer();
    for (nuint i = 0u; i < units; i++)
        into[i] = from[i];
    into[units] = (char16)0u;
    GlobalUnlock(block);
    return block;
}

/// A copy of one format's bytes, from a clipboard this program has open.
///
/// The handle is the clipboard's: locked to read, unlocked after, and never
/// freed. Freeing it is what empties somebody else's clipboard from inside a
/// paste.
byte[] BytesOfOpenFormat(uint format)
{
    HANDLE block = GetClipboardData(format);
    if (block == null)
        return new byte[0u];

    byte* from = (byte*)GlobalLock(block);
    if (from == null)
        return new byte[0u];

    nuint size = GlobalSize(block);
    var bytes = new byte[size];
    for (nuint i = 0u; i < size; i++)
        bytes[i] = from[i];
    GlobalUnlock(block);
    return bytes;
}

/// A copy of one format's bytes, or an empty array.
byte[] ReadClipboardFormat(uint format)
{
    if (!ClipboardOffers(format))
        return new byte[0u];
    if (!OpenClipboardPatiently())
        return new byte[0u];

    var bytes = BytesOfOpenFormat(format);
    CloseClipboard();
    return bytes;
}

// ============================================================ little-endian

uint UIntAt(byte[] data, nuint at)
{
    return (uint)data[at] | ((uint)data[at + 1u] << 8)
         | ((uint)data[at + 2u] << 16) | ((uint)data[at + 3u] << 24);
}

uint UShortAt(byte[] data, nuint at) => (uint)data[at] | ((uint)data[at + 1u] << 8);

void PutUInt(byte[] data, nuint at, uint value)
{
    data[at] = (byte)(value & 0xFFu);
    data[at + 1u] = (byte)((value >> 8) & 0xFFu);
    data[at + 2u] = (byte)((value >> 16) & 0xFFu);
    data[at + 3u] = (byte)((value >> 24) & 0xFFu);
}

void PutUShort(byte[] data, nuint at, uint value)
{
    data[at] = (byte)(value & 0xFFu);
    data[at + 1u] = (byte)((value >> 8) & 0xFFu);
}

// ===================================================================== text

String ReadClipboardText()
{
    if (!ClipboardOffers(ClipboardUnicodeText))
        return "";
    if (!OpenClipboardPatiently())
        return "";

    String text = "";
    HANDLE block = GetClipboardData(ClipboardUnicodeText);
    if (block != null)
    {
        void* units = GlobalLock(block);
        if (units != null)
        {
            // Up to the terminator, and never past the block: a program that
            // left the terminator off would otherwise be read beyond it.
            nuint capacity = GlobalSize(block) / 2u;
            char16* at = (char16*)units;
            nuint length = 0u;
            while (length < capacity && at[length] != (char16)0u)
                length++;
            text = Text.FromUtf16(at, length);
            GlobalUnlock(block);
        }
    }

    CloseClipboard();
    return text;
}

// ===================================================================== HTML
//
// `CF_HTML` is UTF-8 behind a header of byte offsets:
//
//     Version:0.9
//     StartHTML:0000000105
//     EndHTML:0000000163
//     StartFragment:0000000141
//     EndFragment:0000000127
//     <html><body><!--StartFragment-->...<!--EndFragment--></body></html>
//
// The numbers are written ten digits wide so that the header's length does not
// depend on them.

static readonly String HtmlPrefix = "<html>\r\n<body>\r\n<!--StartFragment-->";
static readonly String HtmlSuffix = "<!--EndFragment-->\r\n</body>\r\n</html>";

String HtmlOffset(nuint value) => Text.FromInteger(value).PadLeft(10u, "0");

String HtmlHeader(nuint startHtml, nuint endHtml, nuint startFragment, nuint endFragment)
{
    return "Version:0.9\r\n"
         + "StartHTML:" + HtmlOffset(startHtml) + "\r\n"
         + "EndHTML:" + HtmlOffset(endHtml) + "\r\n"
         + "StartFragment:" + HtmlOffset(startFragment) + "\r\n"
         + "EndFragment:" + HtmlOffset(endFragment) + "\r\n";
}

/// A fragment as `CF_HTML`, NUL-terminated.
byte[] EncodeHtmlFormat(String fragment)
{
    nuint header = HtmlHeader(0u, 0u, 0u, 0u).ByteLength();
    nuint startFragment = header + HtmlPrefix.ByteLength();
    nuint endFragment = startFragment + fragment.ByteLength();
    nuint endHtml = endFragment + HtmlSuffix.ByteLength();

    var whole = HtmlHeader(header, endHtml, startFragment, endFragment)
              + HtmlPrefix + fragment + HtmlSuffix;

    nuint size = whole.ByteLength();
    var bytes = new byte[size + 1u];
    byte* from = whole.ToPointer();
    for (nuint i = 0u; i < size; i++)
        bytes[i] = from[i];
    return bytes;
}

/// A header field's number, or -1 when it is missing or malformed.
long HtmlHeaderNumber(String whole, String key)
{
    long at = whole.IndexOf(key);
    if (at < 0)
        return -1;

    nuint from = (nuint)at + key.ByteLength();
    nuint to = from;
    while (to < whole.ByteLength() && whole.GetByteAt(to) >= (byte)'0' && whole.GetByteAt(to) <= (byte)'9')
        to++;
    if (to == from)
        return -1;

    var parsed = Convert.ToLong(whole.Substring(from, to - from));
    if (!parsed.Ok)
        return -1;
    return parsed.Value;
}

/// The fragment `CF_HTML` carries, or the whole document where the offsets
/// are missing or do not fit.
String DecodeHtmlFormat(byte[] data)
{
    nuint length = 0u;
    while (length < data.Length && data[length] != (byte)0)
        length++;
    if (length == 0u)
        return "";

    var whole = Text.FromBytes(&data[0u], length);

    long start = HtmlHeaderNumber(whole, "StartFragment:");
    long end = HtmlHeaderNumber(whole, "EndFragment:");
    if (start >= 0 && end >= start && (nuint)end <= length)
        return Text.FromBytes(&data[(nuint)start], (nuint)(end - start));

    start = HtmlHeaderNumber(whole, "StartHTML:");
    end = HtmlHeaderNumber(whole, "EndHTML:");
    if (start >= 0 && end >= start && (nuint)end <= length)
        return Text.FromBytes(&data[(nuint)start], (nuint)(end - start));

    return whole;
}

// ================================================================= pictures

/// A picture as a DIB: a `BITMAPINFOHEADER`, or a `BITMAPV5HEADER` whose masks
/// say the fourth byte is alpha, and then the rows bottom to top.
///
/// Bottom-up although top-down is legal, because enough programs read a
/// negative height as an error that a picture written that way is a picture
/// half the desktop cannot paste.
byte[] EncodeDib(ClipboardImage picture, bool withAlphaHeader)
{
    nuint header = withAlphaHeader ? 124u : 40u;
    nuint row = (nuint)picture.Width * 4u;
    nuint bits = row * (nuint)picture.Height;
    var dib = new byte[header + bits];

    PutUInt(dib, 0u, (uint)header);
    PutUInt(dib, 4u, (uint)picture.Width);
    PutUInt(dib, 8u, (uint)picture.Height);
    PutUShort(dib, 12u, 1u);
    PutUShort(dib, 14u, 32u);
    PutUInt(dib, 16u, withAlphaHeader ? DibBitFields : DibRgb);
    PutUInt(dib, 20u, (uint)bits);

    if (withAlphaHeader)
    {
        PutUInt(dib, 40u, 0x00FF0000u);
        PutUInt(dib, 44u, 0x0000FF00u);
        PutUInt(dib, 48u, 0x000000FFu);
        PutUInt(dib, 52u, 0xFF000000u);
        PutUInt(dib, 56u, ColourSpaceSrgb);
        PutUInt(dib, 108u, IntentImages);
    }

    var pixels = picture.Pixels;
    for (nuint y = 0u; y < (nuint)picture.Height; y++)
    {
        nuint source = y * row;
        nuint target = header + ((nuint)picture.Height - 1u - y) * row;
        for (nuint x = 0u; x < row; x++)
            dib[target + x] = pixels[source + x];
    }
    return dib;
}

/// One channel of a pixel read through a mask, scaled to eight bits.
uint MaskedChannel(uint value, uint mask)
{
    if (mask == 0u)
        return 0u;

    uint shift = 0u;
    while (((mask >> shift) & 1u) == 0u)
        shift++;
    uint width = 0u;
    while (shift + width < 32u && ((mask >> (shift + width)) & 1u) != 0u)
        width++;

    uint raw = (value & mask) >> shift;
    if (width >= 8u)
        return raw >> (width - 8u);
    return raw * 255u / ((1u << width) - 1u);
}

/// A DIB's pixels as the seam carries them, or null for one this does not
/// read.
///
/// Reads 1, 4 and 8 bits through a palette, 16 and 32 through masks or the
/// defaults, and 24 directly. Not the compressed forms: run-length encoding
/// has not been put on a clipboard this century, and a DIB holding a PNG or a
/// JPEG is something only a printer driver writes.
///
/// Public because it is what another program's bytes meet first, and so what
/// a test has to be able to hand bytes to without going through a clipboard.
public ClipboardImage? DecodeDib(byte[] dib)
{
    if (dib.Length < 40u)
        return null;

    nuint header = (nuint)UIntAt(dib, 0u);
    if (header < 40u || header > dib.Length)
        return null;

    int width = (int)UIntAt(dib, 4u);
    int height = (int)UIntAt(dib, 8u);
    uint depth = UShortAt(dib, 14u);
    uint compression = UIntAt(dib, 16u);
    uint coloursUsed = UIntAt(dib, 32u);

    bool topDown = height < 0;
    if (topDown)
        height = -height;
    if (width <= 0 || height <= 0)
        return null;

    // Where the masks live depends on the header: after a plain
    // `BITMAPINFOHEADER`, and inside every longer one.
    uint red = 0u;
    uint green = 0u;
    uint blue = 0u;
    uint alpha = 0u;
    nuint maskBytes = 0u;
    bool masked = compression == DibBitFields || compression == DibAlphaBitFields;

    if (masked)
    {
        nuint at = 40u;
        if (header == 40u)
            maskBytes = compression == DibAlphaBitFields ? 16u : 12u;
        if (at + 12u > dib.Length)
            return null;
        red = UIntAt(dib, at);
        green = UIntAt(dib, at + 4u);
        blue = UIntAt(dib, at + 8u);
        if ((header >= 56u || compression == DibAlphaBitFields) && at + 16u <= dib.Length)
            alpha = UIntAt(dib, at + 12u);
    }
    else if (compression != DibRgb)
    {
        return null;
    }
    else if (depth == 16u)
    {
        red = 0x7C00u;
        green = 0x03E0u;
        blue = 0x001Fu;
    }

    switch (depth)
    {
        case 1u:
        case 4u:
        case 8u:
        case 16u:
        case 24u:
        case 32u:
            break;
        default:
            return null;
    }

    // Every size below is checked by division against what is there, so a
    // header claiming more rows than the data holds cannot wrap a product.
    nuint stride = (((nuint)width * (nuint)depth + 31u) / 32u) * 4u;
    if ((nuint)height > dib.Length / stride)
        return null;
    nuint bits = stride * (nuint)height;

    // A `CF_DIBV5` that Windows synthesised from a bit-fields `CF_DIB` carries
    // the masks twice: inside the header, and again after it, as though the
    // header were the short one. Taken as such only when they repeat and there
    // is room for them, since a pixel could happen to look like a mask.
    if (masked && header > 40u && header + 12u + bits <= dib.Length
        && UIntAt(dib, header) == red && UIntAt(dib, header + 4u) == green
        && UIntAt(dib, header + 8u) == blue)
    {
        maskBytes = 12u;
    }

    // A colour table always comes before the pixels when `biClrUsed` says it
    // is there -- above eight bits too, where it is only a hint for a palette
    // display and the pixels do not index it.
    nuint paletteSize = (nuint)coloursUsed;
    if (depth <= 8u && paletteSize == 0u)
        paletteSize = (nuint)1u << (nuint)depth;
    nuint palette = header + maskBytes;
    if (palette > dib.Length || paletteSize > (dib.Length - palette) / 4u)
        return null;
    nuint offset = palette + paletteSize * 4u;

    if (bits > dib.Length - offset)
        return null;

    var pixels = new byte[(nuint)width * (nuint)height * 4u];
    bool anyAlpha = false;

    for (nuint y = 0u; y < (nuint)height; y++)
    {
        nuint sourceRow = topDown ? y : (nuint)height - 1u - y;
        nuint source = offset + sourceRow * stride;
        nuint target = y * (nuint)width * 4u;

        for (nuint x = 0u; x < (nuint)width; x++)
        {
            uint b = 0u;
            uint g = 0u;
            uint r = 0u;
            uint a = 255u;

            if (depth <= 8u)
            {
                nuint bit = x * (nuint)depth;
                uint packed = (uint)dib[source + bit / 8u];
                uint index = (packed >> (8u - (uint)(bit % 8u) - depth)) & ((1u << depth) - 1u);
                if ((nuint)index < paletteSize)
                {
                    nuint entry = palette + (nuint)index * 4u;
                    b = (uint)dib[entry];
                    g = (uint)dib[entry + 1u];
                    r = (uint)dib[entry + 2u];
                }
            }
            else if (depth == 24u)
            {
                nuint at = source + x * 3u;
                b = (uint)dib[at];
                g = (uint)dib[at + 1u];
                r = (uint)dib[at + 2u];
            }
            else if (depth == 16u)
            {
                uint value = UShortAt(dib, source + x * 2u);
                r = MaskedChannel(value, red);
                g = MaskedChannel(value, green);
                b = MaskedChannel(value, blue);
            }
            else if (masked)
            {
                uint value = UIntAt(dib, source + x * 4u);
                r = MaskedChannel(value, red);
                g = MaskedChannel(value, green);
                b = MaskedChannel(value, blue);
                if (alpha != 0u)
                {
                    a = MaskedChannel(value, alpha);
                    anyAlpha = anyAlpha || a != 0u;
                }
            }
            else
            {
                nuint at = source + x * 4u;
                b = (uint)dib[at];
                g = (uint)dib[at + 1u];
                r = (uint)dib[at + 2u];
                a = (uint)dib[at + 3u];
                anyAlpha = anyAlpha || a != 0u;
            }

            pixels[target + x * 4u] = (byte)b;
            pixels[target + x * 4u + 1u] = (byte)g;
            pixels[target + x * 4u + 2u] = (byte)r;
            pixels[target + x * 4u + 3u] = (byte)a;
        }
    }

    // A fourth byte that is zero everywhere is padding, not a picture that is
    // entirely invisible: it is what Windows writes when it makes a DIB from
    // a screenshot's `CF_BITMAP`.
    bool fourthByteIsAlpha = depth == 32u && (!masked || alpha != 0u);
    if (fourthByteIsAlpha && !anyAlpha)
    {
        for (nuint i = 3u; i < pixels.Length; i = i + 4u)
            pixels[i] = (byte)255;
    }

    return new ClipboardImage(width, height, pixels);
}

/// The picture on the clipboard, from the best format on offer, or null.
///
/// PNG first, where there is a decoder, since it is the format whose alpha is
/// never in doubt. Then the DIBs, which Windows synthesises from one another
/// and from `CF_BITMAP`, so a screenshot arrives as either.
ClipboardImage? ReadClipboardImage()
{
    if (ClipboardOffers(PngFormat()) && Standard.Drawing.Imaging.Available)
    {
        var decoded = Standard.Drawing.Image.FromBytes(ReadClipboardFormat(PngFormat()));
        if (decoded.Ok)
        {
            var pixels = decoded.Value.ToBgra();
            if (pixels.Length != 0u)
                return new ClipboardImage(decoded.Value.Width, decoded.Value.Height, pixels);
        }
    }

    if (ClipboardOffers(ClipboardDibV5))
    {
        var found = DecodeDib(ReadClipboardFormat(ClipboardDibV5));
        if (found != null)
            return found;
    }

    if (ClipboardOffers(ClipboardDib))
        return DecodeDib(ReadClipboardFormat(ClipboardDib));
    return null;
}

/// The picture as PNG, or an empty array where there is no encoder.
byte[] EncodePng(ClipboardImage picture)
{
    if (!Standard.Drawing.Imaging.Available)
        return new byte[0u];

    var made = Standard.Drawing.Image.FromBgra(picture.Width, picture.Height, picture.Pixels);
    if (!made.Ok)
        return new byte[0u];

    var encoded = made.Value.Encode(Standard.Drawing.ImageFormat.Png);
    if (!encoded.Ok)
        return new byte[0u];
    return encoded.Value;
}

// ==================================================================== files

/// Paths as `CF_HDROP`: a `DROPFILES` header, then each path in UTF-16 with a
/// terminator, then one more terminator.
byte[] EncodeDropFiles(String[] paths)
{
    nuint header = 20u;

    var wide = new List<Utf16String>();
    nuint units = 1u;
    for (nuint i = 0u; i < paths.Length; i++)
    {
        var path = paths[i].ToUtf16();
        units = units + path.UnitCount() + 1u;
        wide.Add(path);
    }

    var bytes = new byte[header + units * 2u];
    PutUInt(bytes, 0u, (uint)header);
    // `fWide`: the names are UTF-16. The point and `fNC` stay zero.
    PutUInt(bytes, 16u, 1u);

    nuint at = header;
    for (nuint i = 0u; i < wide.Count; i++)
    {
        var path = wide[i];
        char16* from = path.ToPointer();
        for (nuint unit = 0u; unit < path.UnitCount(); unit++)
        {
            PutUShort(bytes, at, (uint)from[unit]);
            at = at + 2u;
        }
        at = at + 2u;
    }
    return bytes;
}

/// The paths on the clipboard, or an empty array.
///
/// Through `DragQueryFileW`, which reads both the UTF-16 and the ANSI form of
/// `DROPFILES`. Never `DragFinish`: the block is the clipboard's.
String[] ReadClipboardFiles()
{
    if (!ClipboardOffers(ClipboardHDrop))
        return new String[0u];
    if (!OpenClipboardPatiently())
        return new String[0u];

    var found = new List<String>();
    HDROP drop = (HDROP)(void*)GetClipboardData(ClipboardHDrop);
    if (drop != null)
    {
        uint count = DragQueryFileW(drop, 0xFFFFFFFFu, null, 0u);
        for (uint i = 0u; i < count; i++)
        {
            uint length = DragQueryFileW(drop, i, null, 0u);
            var buffer = new char16[(nuint)length + 1u];
            uint written = DragQueryFileW(drop, i, &buffer[0u], length + 1u);
            found.Add(Text.FromUtf16(&buffer[0u], (nuint)written));
        }
    }

    CloseClipboard();
    return found.ToArray();
}

// ============================================================ putting it on

/// Replaces the clipboard with everything `content` holds.
///
/// Every block is made before the clipboard is opened, so that it is held for
/// as long as `SetClipboardData` takes and no longer. A block the clipboard
/// did not take is freed; one it took belongs to the system from then on.
void WriteClipboard(ClipboardContent content)
{
    var formats = new List<uint>();
    var blocks = new List<nuint>();

    var text = content.Text;
    if (text != null)
    {
        formats.Add(ClipboardUnicodeText);
        blocks.Add((nuint)(void*)BlockHoldingUtf16((String)text));
    }

    var html = content.Html;
    if (html != null)
    {
        formats.Add(HtmlFormat());
        blocks.Add((nuint)(void*)BlockHoldingBytes(EncodeHtmlFormat((String)html)));
    }

    var image = content.Image;
    if (image != null)
    {
        var picture = (ClipboardImage)image;
        formats.Add(ClipboardDib);
        blocks.Add((nuint)(void*)BlockHoldingBytes(EncodeDib(picture, false)));
        formats.Add(ClipboardDibV5);
        blocks.Add((nuint)(void*)BlockHoldingBytes(EncodeDib(picture, true)));

        var png = EncodePng(picture);
        if (png.Length != 0u)
        {
            formats.Add(PngFormat());
            blocks.Add((nuint)(void*)BlockHoldingBytes(png));
        }
    }

    if (content.Files.Length != 0u)
    {
        formats.Add(ClipboardHDrop);
        blocks.Add((nuint)(void*)BlockHoldingBytes(EncodeDropFiles(content.Files)));

        // Explorer pastes as a copy unless told otherwise, so this changes
        // nothing there; it is for the file managers that ask.
        var effect = new byte[4u];
        PutUInt(effect, 0u, DropEffectCopy);
        formats.Add(DropEffectFormat());
        blocks.Add((nuint)(void*)BlockHoldingBytes(effect));
    }

    for (nuint i = 0u; i < content.Custom.Count; i++)
    {
        var entry = content.Custom[i];
        formats.Add(RegisterFormatNamed(entry.Name));
        blocks.Add((nuint)(void*)BlockHoldingBytes(entry.Data));
    }

    if (!OpenClipboardPatiently())
    {
        for (nuint i = 0u; i < blocks.Count; i++)
        {
            if (blocks[i] != 0u)
                GlobalFree((HGLOBAL)(void*)blocks[i]);
        }
        return;
    }

    EmptyClipboard();
    for (nuint i = 0u; i < formats.Count; i++)
    {
        HGLOBAL block = (HGLOBAL)(void*)blocks[i];
        if (block == null)
            continue;
        if (formats[i] == 0u || SetClipboardData(formats[i], block) == null)
            GlobalFree(block);
    }
    CloseClipboard();
}

/// Every format on offer, by name.
String[] ReadClipboardFormatNames()
{
    if (!OpenClipboardPatiently())
        return new String[0u];

    var names = new List<String>();
    uint format = EnumClipboardFormats(0u);
    while (format != 0u)
    {
        names.Add(NameOfClipboardFormat(format));
        format = EnumClipboardFormats(format);
    }

    CloseClipboard();
    return names.ToArray();
}

// ================================================================ watching

/// The property a clipboard watch's window hangs its peer on, beside the
/// timer's and for the same reason: it is not a control.
static readonly String ClipboardWatchProperty = "StainlessFormsClipboardWatch";

/// A message-only window that asks for `WM_CLIPBOARDUPDATE`.
///
/// One window per watch rather than one listener shared by every watch,
/// because then the watch's lifetime is the window's and nothing has to keep a
/// list of who is still listening.
public class ClipboardWatchPeer : IClipboardWatchPeer
{
    HWND _window;
    weak IClipboardNotify? _target;
    bool _listening;

    public ClipboardWatchPeer(IClipboardNotify owner)
    {
        _target = owner;
        _listening = false;
        EnsureFormClass();
        _window = CreateWindowExW(0u, FormClassName.ToUtf16().ToPointer(),
                                  "".ToUtf16().ToPointer(), 0u, 0, 0, 0, 0,
                                  MessageOnlyParent(), null,
                                  GetModuleHandleW(null), null);
        SetPropW(_window, ClipboardWatchProperty.ToUtf16().ToPointer(), (void*)this);
    }

    ~ClipboardWatchPeer()
    {
        Stop();
        if (_window != null)
        {
            RemovePropW(_window, ClipboardWatchProperty.ToUtf16().ToPointer());
            DestroyWindow(_window);
            _window = null;
        }
    }

    public void Start()
    {
        if (_listening || _window == null)
            return;
        _listening = AddClipboardFormatListener(_window) != 0;
    }

    public void Stop()
    {
        if (!_listening)
            return;
        RemoveClipboardFormatListener(_window);
        _listening = false;
    }

    /// Called by the window procedure when `WM_CLIPBOARDUPDATE` arrives.
    public void Fire()
    {
        IClipboardNotify? held = _target;
        if (held == null)
            return;
        ((IClipboardNotify)held).OnPlatformClipboardChanged();
    }
}

/// The watch behind a window, or null for a window that is not one.
ClipboardWatchPeer? ClipboardWatchOf(HWND window)
{
    if (window == null)
        return null;
    var raw = GetPropW(window, ClipboardWatchProperty.ToUtf16().ToPointer());
    if (raw == null)
        return null;
    return (ClipboardWatchPeer)raw;
}

#endif
