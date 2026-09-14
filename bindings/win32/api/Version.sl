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

// `version.dll`: reading an `RT_VERSION` resource.
//
// This is the one resource type with no `Load...` call beside the others in
// `user32`, and the reason is that it is not one value but a small tree. A
// version resource holds a fixed-size `VS_FIXEDFILEINFO` -- the four-part file
// and product versions, as numbers -- and beside it a set of string tables, one
// per language, holding `CompanyName`, `FileDescription`, `ProductName` and the
// rest as text. `VerQueryValueW` walks that tree by path.
//
// **Three calls, in order.** Ask how big the block is, read it into a buffer
// you own, then query inside it. The buffer must stay alive for as long as
// anything queried out of it is used: `VerQueryValueW` hands back a pointer
// *into* the block rather than a copy, which is the mistake this note exists to
// prevent.
//
// **It reads a file, not a running module.** Every entry point here takes a
// path, so a program asking for its own version asks about its own executable
// -- `GetModuleFileNameW` with a null module is how that path is found.
module Win32.Version;

import Win32.Handles;

#if WINDOWS

// Unlike the rest of the resource API, this one is not in a library every
// program already links.
#pragma comment(lib, "version")

public extern "C" {
    /// How many bytes the version block takes, or zero when the file has no
    /// `RT_VERSION` resource at all. `handle` is ignored and exists because
    /// 16-bit Windows used it.
    uint GetFileVersionInfoSizeW(char16* path, uint* handle);

    /// Reads the block into a buffer of that size.
    int  GetFileVersionInfoW(char16* path, uint handle, uint size, void* buffer);

    /// Looks something up inside the block by path, and hands back a pointer
    /// *into* it rather than a copy.
    ///
    /// The three paths that matter:
    ///
    ///   `\`                                  the `VS_FIXEDFILEINFO`
    ///   `\VarFileInfo\Translation`           which languages are present
    ///   `\StringFileInfo\<lang><cp>\<name>`  one string, for that language
    ///
    /// The language and code page in the third are eight hex digits, which is
    /// what the second hands back as a pair of 16-bit values.
    int  VerQueryValueW(void* block, char16* path, void** value, uint* length);
}

/// `VS_FIXEDFILEINFO`, which is what the `\` path answers.
///
/// The versions are four 16-bit parts packed into two 32-bit words each, most
/// significant first: `1.2.3.4` is `VersionMs = 0x00010002`, `VersionLs =
/// 0x00030004`. `Win32.Resources.FileVersion` unpacks them.
public struct FixedFileInfo {
    public uint Signature;
    public uint StructVersion;
    public uint FileVersionMs;
    public uint FileVersionLs;
    public uint ProductVersionMs;
    public uint ProductVersionLs;
    public uint FileFlagsMask;
    public uint FileFlags;
    public uint FileOs;
    public uint FileType;
    public uint FileSubtype;
    public uint FileDateMs;
    public uint FileDateLs;
}

/// `VS_FFI_SIGNATURE`: what `Signature` holds when the block was read
/// correctly, and the one cheap check that it was.
public const uint FixedFileInfoSignature = 0xFEEF04BDu;

#endif
