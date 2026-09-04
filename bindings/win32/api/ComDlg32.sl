// Stainless - an experimental systems language.
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

// comdlg32.dll: the common dialogs.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l comdlg32`, or `Win32.Dialogs`,
// which names it with a pragma.
module Win32.ComDlg32;

#if WINDOWS

/// `OPENFILENAMEW`. `sizeof` is 152, and `Size` must be set to it.
///
/// `File` points at a buffer the dialog *writes into*, so it must be writable
/// and big enough. `Filter` is stranger: a list of NUL-separated pairs ending
/// in a double NUL, which no Stainless string can hold —
/// `Win32.Dialogs.BuildFilter` assembles one.
public struct OpenFileName {
    public uint    Size;
    public void*   Owner;
    public void*   Instance;
    public ushort* Filter;
    public ushort* CustomFilter;
    public uint    CustomFilterMax;
    public uint    FilterIndex;
    public ushort* File;
    public uint    FileMax;
    public ushort* FileTitle;
    public uint    FileTitleMax;
    public ushort* InitialDirectory;
    public ushort* Title;
    public uint    Flags;
    public ushort  FileOffset;
    public ushort  ExtensionOffset;
    public ushort* DefaultExtension;
    public long    CustomData;
    public void*   Hook;
    public ushort* TemplateName;
    public void*   Reserved1;
    public uint    Reserved2;
    public uint    FlagsEx;
}

public const uint OfnReadOnly           = 0x00000001u;
public const uint OfnOverwritePrompt    = 0x00000002u;
public const uint OfnHideReadOnly       = 0x00000004u;
public const uint OfnNoChangeDir        = 0x00000008u;
public const uint OfnAllowMultiSelect   = 0x00000200u;
public const uint OfnPathMustExist      = 0x00000800u;
public const uint OfnFileMustExist      = 0x00001000u;
public const uint OfnCreatePrompt       = 0x00002000u;
public const uint OfnExplorer           = 0x00080000u;
public const uint OfnNoDereferenceLinks = 0x00100000u;

public extern "C" {
    int  GetOpenFileNameW(OpenFileName* dialog);
    int  GetSaveFileNameW(OpenFileName* dialog);
    uint CommDlgExtendedError();
}

#endif
