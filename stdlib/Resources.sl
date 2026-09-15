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

/// What a program carries inside itself, on every platform.
///
/// A `.rc` listed among a build's sources is compiled by `llvm-rc` and folded
/// into the binary, and this reads it back:
///
/// ```csharp
/// import Standard.Resources;
///
/// String ready = Resources.Text(201u);
/// byte[] icon  = Resources.Bytes(Resources.Bitmap, 101);
/// ```
///
/// **The same answers on both platforms, by two different routes.** A PE has a
/// resource directory and the loader indexes it, so a Windows build asks
/// `FindResourceW` and gets a pointer into the mapped image. ELF has no such
/// section, so the compiler puts the compiled `.res` in ordinary constant data
/// and this walks it. Both were checked against each other on the same script,
/// entry by entry, which is the only reason the claim is worth making.
///
/// **What travels and what does not.** Bytes travel: `RT_RCDATA`, `RT_BITMAP`,
/// `RT_STRING`, `RT_HTML` and a type a script invents are all readable
/// anywhere. What does not travel is the part where the *operating system*
/// reads the resource on the program's behalf -- an `RT_MANIFEST` selects
/// comctl32 version 6, an `RT_GROUP_ICON` becomes the window's icon, and an
/// `RT_DIALOG` becomes a window full of controls, none of which anything
/// outside Windows does. Those are readable here as bytes and mean nothing.
///
/// **Nothing is freed.** A resource lives in the loaded image on both routes,
/// so `Pointer` hands back memory that is already there and stays valid as long
/// as the program runs. It must not be written through. `Bytes` copies, which
/// is what anything outliving the call wants.
module Standard.Resources;

import Standard.Collections;

// ================================================================== types

/// The `RT_` numbers, which mean what they mean in `winuser.h` because that is
/// what the resource compiler writes.
public const int Cursor       = 1;
public const int Bitmap       = 2;
public const int Icon         = 3;
public const int Menu         = 4;
public const int Dialog       = 5;
public const int StringTable  = 6;
public const int Accelerator  = 9;
public const int RcData       = 10;
public const int MessageTable = 11;
public const int GroupCursor  = 12;
public const int GroupIcon    = 14;
public const int Version      = 16;
public const int Html         = 23;
public const int Manifest     = 24;

/// `CREATEPROCESS_MANIFEST_RESOURCE_ID`: the name an executable's own manifest
/// is filed under.
public const int ManifestId = 1;

// ============================================================ the platform

#if WINDOWS

// kernel32 only, and deliberately. `LoadStringW` would be the obvious way to
// read a string table and it lives in user32, which would make every program
// that touches a resource link a library it may want nothing else from. The
// block arithmetic `LoadStringW` performs is thirty lines and is written out
// below, so this needs nothing but the three calls that hand back bytes -- and
// kernel32 comes with the C runtime every Windows program already links.
// `__stdcall` because that is what `WINAPI` is. It means nothing on x64,
// which has one calling convention, and everything on x86, where the import
// library exports `_GetModuleHandleW@4` and a cdecl declaration goes looking
// for `_GetModuleHandleW`.
extern "C" __stdcall
{
    void* GetModuleHandleW(char16* name);
    void* FindResourceW(void* library, char16* name, char16* type);
    void* LoadResource(void* library, void* resource);
    void* LockResource(void* loaded);
    uint  SizeofResource(void* library, void* resource);
}

/// A resource's bytes, or null. `MAKEINTRESOURCE` is the cast: Windows
/// reserves the bottom 64K of the pointer range for an integer name.
byte* FindBytes(int type, int id, uint* byteCount)
{
    if (byteCount != null)
        *byteCount = 0u;

    void* self = GetModuleHandleW(null);
    void* found = FindResourceW(self, (char16*)(nuint)(uint)id, (char16*)(nuint)(uint)type);
    if (found == null)
        return null;

    void* at = LockResource(LoadResource(self, found));
    if (at == null)
        return null;

    if (byteCount != null)
        *byteCount = SizeofResource(self, found);
    return (byte*)at;
}

/// The same, for a resource named by text rather than by number.
byte* FindNamedBytes(String type, String name, uint* byteCount)
{
    if (byteCount != null)
        *byteCount = 0u;

    var wideType = type.ToUtf16();
    var wideName = name.ToUtf16();

    void* self = GetModuleHandleW(null);
    void* found = FindResourceW(self, wideName.ToPointer(), wideType.ToPointer());
    if (found == null)
        return null;

    void* at = LockResource(LoadResource(self, found));
    if (at == null)
        return null;

    if (byteCount != null)
        *byteCount = SizeofResource(self, found);
    return (byte*)at;
}

#else

// The compiled `.res`, emitted by the compiler as ordinary constant data
// because an ELF binary has nowhere else to put it. The symbols' *addresses*
// are the blob, which is why the declaration is a `byte` and the use is `&`.
//
// Always emitted, empty when the program has no resources, so that this links
// whether or not anything was compiled in.
extern "C" byte  sl_resource_blob;
extern "C" ulong sl_resource_blob_size;

byte* BlobStart() => &sl_resource_blob;
nuint BlobSize() => (nuint)sl_resource_blob_size;

/// A resource's bytes, found by walking the `.res` records.
byte* FindBytes(int type, int id, uint* byteCount)
{
    return Walk(type, "", id, "", byteCount, true, true);
}

byte* FindNamedBytes(String type, String name, uint* byteCount)
{
    return Walk(0, type, 0, name, byteCount, false, false);
}

// ------------------------------------------------------- the .res format
//
// A flat list of records, each starting on a four-byte boundary:
//
//     DWORD DataSize          how many bytes of payload
//     DWORD HeaderSize        from the start of this record to the payload
//     type                    0xFFFF then a 16-bit id, or NUL-terminated UTF-16
//     name                    the same
//     (padding to four)
//     DWORD DataVersion
//     WORD  MemoryFlags
//     WORD  LanguageId
//     DWORD Version
//     DWORD Characteristics
//     payload, then padding to four
//
// `HeaderSize` is what makes the two variable-length fields bearable: the
// payload is found without parsing either of them. A file opens with a null
// marker -- every field zero -- and a blob built from several scripts has one
// wherever they were joined, so a marker is skipped wherever it appears rather
// than only at the front.

uint ReadU16(byte* at, nuint offset)
{
    return (uint)at[offset] | ((uint)at[offset + 1u] << 8);
}

uint ReadU32(byte* at, nuint offset)
{
    return (uint)at[offset]
         | ((uint)at[offset + 1u] << 8)
         | ((uint)at[offset + 2u] << 16)
         | ((uint)at[offset + 3u] << 24);
}

/// Steps over a type or a name, and answers where the next field starts.
nuint SkipName(byte* blob, nuint at, nuint size, out bool isId, out int id, out nuint textAt)
{
    isId = false;
    id = 0;
    textAt = 0u;

    if (ReadU16(blob, at) == 0xFFFFu)
    {
        isId = true;
        id = (int)ReadU16(blob, at + 2u);
        return at + 4u;
    }

    textAt = at;
    nuint cursor = at;
    while (cursor + 2u <= size && ReadU16(blob, cursor) != 0u)
        cursor = cursor + 2u;
    return cursor + 2u;
}

bool TextEquals(byte* blob, nuint at, String expected)
{
    nuint units = 0u;
    while (ReadU16(blob, at + units * 2u) != 0u)
        units = units + 1u;
    return Text.FromUtf16((char16*)(void*)(blob + at), units) == expected;
}

/// Walks the blob for one resource. A match is by number or by text on each
/// half independently, which is what the two flags choose between.
byte* Walk(int type, String typeName, int id, String name,
           uint* byteCount, bool typeIsNumber, bool nameIsNumber)
{
    if (byteCount != null)
        *byteCount = 0u;

    byte* blob = BlobStart();
    nuint size = BlobSize();
    nuint at = 0u;

    while (at + 8u <= size)
    {
        uint dataSize = ReadU32(blob, at);
        uint headerSize = ReadU32(blob, at + 4u);

        // A header shorter than its own fixed part, or one running off the end,
        // means this is not a .res -- stop rather than read whatever follows.
        if (headerSize < 32u || at + (nuint)headerSize > size)
            return null;

        bool foundTypeIsId;
        int foundTypeId;
        nuint typeAt;
        nuint cursor = SkipName(blob, at + 8u, size,
                                out foundTypeIsId, out foundTypeId, out typeAt);

        bool foundNameIsId;
        int foundNameId;
        nuint nameAt;
        cursor = SkipName(blob, cursor, size,
                          out foundNameIsId, out foundNameId, out nameAt);

        nuint dataAt = at + (nuint)headerSize;

        bool typeMatches = typeIsNumber
            ? foundTypeIsId && foundTypeId == type
            : !foundTypeIsId && TextEquals(blob, typeAt, typeName);

        bool nameMatches = nameIsNumber
            ? foundNameIsId && foundNameId == id
            : !foundNameIsId && TextEquals(blob, nameAt, name);

        // A null marker matches nothing, because its type and name are zero and
        // no resource is filed under either.
        if (typeMatches && nameMatches && dataSize > 0u)
        {
            if (byteCount != null)
                *byteCount = dataSize;
            return blob + dataAt;
        }

        nuint next = (dataAt + (nuint)dataSize + 3u) & ~(nuint)3u;
        if (next <= at)
            return null;
        at = next;
    }

    return null;
}

#endif

// ================================================================ reading

/// Whether a resource of this type and number is there.
public bool Exists(int type, int id) => FindBytes(type, id, null) != null;

/// Whether one named by text, of a type named by text, is there.
public bool Exists(String type, String name)
{
    return FindNamedBytes(type, name, null) != null;
}

/// How many bytes a resource holds, or zero when there is none.
public uint Size(int type, int id)
{
    uint count = 0u;
    FindBytes(type, id, &count);
    return count;
}

/// A pointer straight at a resource's bytes, without copying them.
///
/// The memory belongs to the loaded image: read-only, never freed, and valid
/// for as long as the program runs. `Bytes` is the one to use for anything that
/// outlives the call.
public byte* Pointer(int type, int id, uint* byteCount)
{
    return FindBytes(type, id, byteCount);
}

/// A resource's bytes, copied into an array this program owns.
///
/// Empty when there is no such resource, which is also what an empty resource
/// gives -- ask `Exists` where the difference matters.
public byte[] Bytes(int type, int id)
{
    uint count = 0u;
    byte* at = FindBytes(type, id, &count);
    return CopyOut(at, count);
}

/// The same, for a resource named by text.
public byte[] Bytes(String type, String name)
{
    uint count = 0u;
    byte* at = FindNamedBytes(type, name, &count);
    return CopyOut(at, count);
}

byte[] CopyOut(byte* at, uint count)
{
    if (at == null || count == 0u)
        return new byte[0];

    var copy = new byte[(nuint)count];
    for (nuint i = 0u; i < (nuint)count; i = i + 1u)
        copy[i] = at[i];
    return copy;
}

// ================================================================ strings

/// One string from a string table, by the number the script gave it.
///
/// **A string is not a resource of its own.** The resource compiler files them
/// sixteen to a block: the block's name is `id / 16 + 1`, and inside it each of
/// the sixteen slots is a 16-bit length followed by that many UTF-16 units,
/// with a length of zero meaning nothing is filed at that slot. `LoadStringW`
/// does this arithmetic on Windows; it is written out here so that both
/// platforms answer identically and so that Windows needs no user32.
///
/// Empty for a number with no string, which is what `LoadStringW` answers too.
public String Text(uint id)
{
    uint count = 0u;
    byte* block = FindBytes(StringTable, (int)(id / 16u) + 1, &count);
    if (block == null)
        return "";

    nuint within = (nuint)(id % 16u);
    nuint cursor = 0u;
    nuint limit = (nuint)count;

    for (nuint slot = 0u; slot < 16u; slot = slot + 1u)
    {
        if (cursor + 2u > limit)
            return "";

        nuint units = (nuint)((uint)block[cursor] | ((uint)block[cursor + 1u] << 8));
        cursor = cursor + 2u;

        if (slot == within)
        {
            if (units == 0u || cursor + units * 2u > limit)
                return "";
            return Text.FromUtf16((char16*)(void*)(block + cursor), units);
        }

        cursor = cursor + units * 2u;
    }

    return "";
}

// ================================================================ bitmaps

/// A `RT_BITMAP` as a whole `.bmp` file.
///
/// **The resource is not a file.** The resource compiler strips the 14-byte
/// `BITMAPFILEHEADER`, because Windows never wants it -- `LoadImageW` is handed
/// the `BITMAPINFOHEADER` onwards and knows what to do. Anything else that
/// decodes an image expects a whole file, so this puts the header back.
///
/// The pixel offset is not guesswork: the DIB header says how long it is, and
/// the palette between it and the pixels is `biClrUsed` entries of four bytes,
/// or the full `2^depth` when that field is zero and the depth is 8 or fewer.
///
/// Empty when there is no such bitmap.
public byte[] BitmapFile(int id)
{
    var stored = Bytes(Bitmap, id);
    if (stored.Length < 40)
        return new byte[0];

    nuint dibSize = (nuint)stored[0u]
                  | ((nuint)stored[1u] << 8)
                  | ((nuint)stored[2u] << 16)
                  | ((nuint)stored[3u] << 24);

    nuint depth = (nuint)stored[14u] | ((nuint)stored[15u] << 8);
    nuint used  = (nuint)stored[32u]
                | ((nuint)stored[33u] << 8)
                | ((nuint)stored[34u] << 16)
                | ((nuint)stored[35u] << 24);

    nuint palette = used;
    if (palette == 0u && depth <= 8u)
        palette = (nuint)1u << (int)depth;

    nuint offset = 14u + dibSize + palette * 4u;
    nuint total  = 14u + (nuint)stored.Length;

    var file = new byte[total];
    file[0u] = 66u;                                  // 'B'
    file[1u] = 77u;                                  // 'M'
    file[2u] = (byte)(total & 255u);
    file[3u] = (byte)((total >> 8) & 255u);
    file[4u] = (byte)((total >> 16) & 255u);
    file[5u] = (byte)((total >> 24) & 255u);
    file[10u] = (byte)(offset & 255u);
    file[11u] = (byte)((offset >> 8) & 255u);
    file[12u] = (byte)((offset >> 16) & 255u);
    file[13u] = (byte)((offset >> 24) & 255u);

    for (nuint i = 0u; i < (nuint)stored.Length; i = i + 1u)
    {
        file[14u + i] = stored[i];
    }
    return file;
}
