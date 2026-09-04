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

// advapi32.dll: the registry.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l advapi32`, or `Win32.Registry`,
// which names it with a pragma.
//
// The registry is the one part of Win32 that does not use `GetLastError`: every
// `Reg...` function *returns* its error code, and returns `ErrorSuccess` when
// it worked. These declarations pass that through unchanged; `Win32.Registry`
// is the layer that turns it into a `Result`.
module Win32.AdvApi32;

import Win32.Handles;

#if WINDOWS

import Win32.Kernel32;

public extern "C" {
    int RegOpenKeyExW(HKEY key, ushort* path, uint options, uint access, HKEY* result);
    int RegCreateKeyExW(HKEY key, ushort* path, uint reserved, ushort* windowClass,
                        uint options, uint access, SecurityAttributes* security,
                        HKEY* result, uint* disposition);
    int RegCloseKey(HKEY key);
    int RegQueryValueExW(HKEY key, ushort* name, uint* reserved, uint* kind,
                         byte* data, uint* size);
    int RegSetValueExW(HKEY key, ushort* name, uint reserved, uint kind,
                       byte* data, uint size);
    int RegDeleteValueW(HKEY key, ushort* name);
    int RegDeleteKeyW(HKEY key, ushort* path);
    int RegEnumKeyExW(HKEY key, uint index, ushort* name, uint* nameSize,
                      uint* reserved, ushort* windowClass, uint* classSize,
                      FileTime* lastWrite);
    int RegEnumValueW(HKEY key, uint index, ushort* name, uint* nameSize,
                      uint* reserved, uint* kind, byte* data, uint* dataSize);
    int RegQueryInfoKeyW(HKEY key, ushort* windowClass, uint* classSize,
                         uint* reserved, uint* subkeys, uint* maxSubkeyLength,
                         uint* maxClassLength, uint* values, uint* maxValueNameLength,
                         uint* maxValueLength, uint* securityDescriptor,
                         FileTime* lastWrite);
    int RegFlushKey(HKEY key);

    int GetUserNameW(ushort* buffer, uint* size);
}

// ================================================================= the roots

/// The predefined keys. They are pointer-shaped constants rather than handles
/// anything opened, so they are never closed — and functions rather than
/// `const`, because Stainless has no `const` pointer.
public HKEY ClassesRoot()   { return (HKEY)(nuint)0x80000000u; }
public HKEY CurrentUser()   { return (HKEY)(nuint)0x80000001u; }
public HKEY LocalMachine()  { return (HKEY)(nuint)0x80000002u; }
public HKEY Users()         { return (HKEY)(nuint)0x80000003u; }
public HKEY CurrentConfig() { return (HKEY)(nuint)0x80000005u; }

// =================================================================== access

public const uint KeyQueryValue       = 0x0001u;
public const uint KeySetValue         = 0x0002u;
public const uint KeyCreateSubKey     = 0x0004u;
public const uint KeyEnumerateSubKeys = 0x0008u;
public const uint KeyNotify           = 0x0010u;
public const uint KeyCreateLink       = 0x0020u;

/// `KEY_READ` and `KEY_WRITE`, which are the two a program normally wants.
public const uint KeyRead      = 0x20019u;
public const uint KeyWrite     = 0x20006u;
public const uint KeyAllAccess = 0xF003Fu;

/// Which view of the registry to use on a 64-bit system, where a 32-bit program
/// is redirected into `Wow6432Node` unless it says otherwise.
public const uint KeyWow6464Key = 0x0100u;
public const uint KeyWow6432Key = 0x0200u;

// ==================================================================== kinds

public const uint KindNone         = 0u;
public const uint KindString       = 1u;    // REG_SZ
public const uint KindExpandString = 2u;    // REG_EXPAND_SZ
public const uint KindBinary       = 3u;
public const uint KindUInt         = 4u;    // REG_DWORD
public const uint KindMultiString  = 7u;
public const uint KindULong        = 11u;   // REG_QWORD

#endif
