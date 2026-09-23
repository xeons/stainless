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

module Standard.Resources;

import Standard.Collections;

// ================================================================== types

/// The `RT_` numbers, which mean what they mean in `winuser.h` because that is
/// what the resource compiler writes.
///
/// An enum rather than fourteen constants at module level, because `Icon`,
/// `Menu`, `Dialog` and `Version` are words an importer has other uses for.
public enum ResourceType
{
    /// `RT_CURSOR`.
    Cursor       = 1,

    /// `RT_BITMAP`, without the file header; `GetBitmapFile` puts one back.
    Bitmap       = 2,

    /// `RT_ICON`.
    Icon         = 3,

    /// `RT_MENU`.
    Menu         = 4,

    /// `RT_DIALOG`.
    Dialog       = 5,

    /// `RT_STRING`; `GetText` reads one entry out of a block of sixteen.
    StringTable  = 6,

    /// `RT_ACCELERATOR`.
    Accelerator  = 9,

    /// `RT_RCDATA`, which is bytes and nothing else, and so the one that
    /// travels to every platform unchanged.
    RcData       = 10,

    /// `RT_MESSAGETABLE`.
    MessageTable = 11,

    /// `RT_GROUP_CURSOR`.
    GroupCursor  = 12,

    /// `RT_GROUP_ICON`.
    GroupIcon    = 14,

    /// `RT_VERSION`.
    Version      = 16,

    /// `RT_HTML`.
    Html         = 23,

    /// `RT_MANIFEST`, read by the loader rather than by the program.
    Manifest     = 24,
}
