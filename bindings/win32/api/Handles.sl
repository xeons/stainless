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


// The handle types, as `windef.h` declares them.
//
// Windows writes every handle as `DECLARE_HANDLE(HWND)`, which expands to a
// struct nothing ever defines and a pointer to it. The struct exists purely so
// that `HWND` and `HDC` are different types: nothing knows what a window is,
// and the only thing anyone does with one is hand it back. This says the same,
// with the same spellings, so that a signature found on MSDN reads across.
//
// It costs nothing. None of these types is laid out, emitted, or present at run
// time; what crosses the boundary is a pointer, exactly as `void*` did. What it
// buys is that passing a device context where a window belongs is caught:
//
//     error[SL0262]: argument 1 of 'ShowWindow' expects 'HWND__*',
//     but 'HDC__*' was given
//
// The `__` suffix is Windows' own, and is worth keeping for the same reason it
// has it: the tag is the name a diagnostic shows.
//
// This is not a DLL, which every other module here is named after. It is the
// header those DLLs are declared in terms of, and it is separate for the same
// reason `windef.h` is: `HWND` belongs to no one library.
module Win32.Handles;

#if WINDOWS

// ================================================================== the tags
//
// Declared and never defined, so a value of one cannot exist and a pointer to
// one is a type of its own.

public struct HANDLE__;
public struct HWND__;
public struct HDC__;
public struct HMENU__;
public struct HICON__;
public struct HBRUSH__;
public struct HPEN__;
public struct HFONT__;
public struct HBITMAP__;
public struct HINSTANCE__;
public struct HKEY__;
public struct HDROP__;

// ================================================================ the handles

/// Anything the kernel counts: a file, a pipe, a process, a thread, an event,
/// a heap, a directory walk, a console screen buffer.
public using HANDLE = HANDLE__*;

/// A window.
public using HWND = HWND__*;

/// A device context: where drawing goes.
public using HDC = HDC__*;

/// A menu.
public using HMENU = HMENU__*;

/// An icon.
public using HICON = HICON__*;

/// A cursor. `windef.h` says `typedef HICON HCURSOR;`, and so does this: the
/// two are one type under two names, which is what an alias is for.
public using HCURSOR = HICON;

public using HBRUSH  = HBRUSH__*;
public using HPEN    = HPEN__*;
public using HFONT   = HFONT__*;
public using HBITMAP = HBITMAP__*;

/// A loaded module. `windef.h` says `typedef HINSTANCE HMODULE;`, because a
/// module handle *is* the address it was loaded at.
public using HINSTANCE = HINSTANCE__*;
public using HMODULE   = HINSTANCE;

/// A registry key.
public using HKEY = HKEY__*;

/// A dropped-files list, from `WM_DROPFILES`.
public using HDROP = HDROP__*;

/// Memory from `GlobalAlloc` and `LocalAlloc`. Both are `HANDLE` in `windef.h`,
/// and both are here.
public using HGLOBAL = HANDLE;
public using HLOCAL  = HANDLE;

/// Any GDI object: a pen, a brush, a font, a bitmap, a region.
///
/// `windef.h` spells it `typedef void *HGDIOBJ;` precisely so that every one of
/// those converts to it without a cast, and `SelectObject` can take all of
/// them. Here that role belongs to `byte*` — the one pointer type every other
/// converts to — so this is that, for the same reason and with the same effect.
public using HGDIOBJ = byte*;

#endif
