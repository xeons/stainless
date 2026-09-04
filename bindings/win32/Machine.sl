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

// What the machine is, what memory it has, and the modules loaded into this
// process.
//
// A convenience layer over `Win32.Kernel32`. Nothing here needs a `-l`.
module Win32.Machine;

#if WINDOWS

import Win32;
import Win32.Kernel32;
import Win32.Handles;

// =================================================================== system

/// Page size, processor count and the rest, as the running process sees it.
/// Under WOW64 that is the emulated view; `NativeInfo()` is the real one.
public SystemInfo Info() {
    SystemInfo info;
    GetSystemInfo(&info);
    return info;
}

public SystemInfo NativeInfo() {
    SystemInfo info;
    GetNativeSystemInfo(&info);
    return info;
}

/// How much memory there is and how much is free. The `Length` field is filled
/// in here, because the call fails without it.
public MemoryStatus Memory() {
    MemoryStatus status;
    status.Length = (uint)sizeof(MemoryStatus);
    GlobalMemoryStatusEx(&status);
    return status;
}

/// `x64`, `arm64`, `x86`, `arm`, or the number for anything else.
///
/// `Info().Architecture` is where the number comes from: `SYSTEM_INFO`'s first
/// word is a nameless union in the header and here, so the field reads directly
/// off the struct rather than through a name Windows never gave it.
public String ArchitectureName(ushort code) {
    if (code == ProcessorArchitectureX64)   { return "x64"; }
    if (code == ProcessorArchitectureArm64) { return "arm64"; }
    if (code == ProcessorArchitectureX86)   { return "x86"; }
    if (code == ProcessorArchitectureArm)   { return "arm"; }
    return "unknown (" + Text.FromInteger((long)code) + ")";
}

/// Writes to the debugger's output window, and nowhere at all when no debugger
/// is attached.
public void DebugPrint(String text) {
    OutputDebugStringW(text.ToUtf16().ToPointer());
}

// ==================================================================== pages

/// Reserves and commits read-write pages in one call, which is what a caller
/// that just wants memory means.
public void* AllocatePages(nuint size) {
    return VirtualAlloc(null, size, MemCommit | MemReserve, PageReadWrite);
}

/// Releases what `AllocatePages` returned. The size must be zero for
/// `MEM_RELEASE`, which is a rule of the API rather than of this binding.
public bool ReleasePages(void* at) {
    return Win32.Succeeded(VirtualFree(at, 0u, MemRelease));
}

// ================================================================== modules

/// Loads a DLL by name or path, or null on failure.
///
/// `GetProcAddress` takes an *ANSI* name even in a wide program, because an
/// export name is bytes in the file rather than text — which is why its
/// declaration takes a `byte*` and a Stainless string literal reaches it
/// directly.
public HMODULE LoadLibrary(String name) {
    return LoadLibraryW(name.ToUtf16().ToPointer());
}

/// The full path of the running .exe, or of a loaded DLL when given its handle.
public String ModulePath(HMODULE library) {
    var buffer = new WideBuffer(32768u);
    uint units = GetModuleFileNameW(library, buffer.Pointer(), buffer.Capacity());
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

/// The full path of the running executable.
public String ExecutablePath() { return ModulePath(null); }

#endif
