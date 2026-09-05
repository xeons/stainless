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

// ole32.dll: COM's activation half.
//
// The language supplies the other half. `com interface` and `com class` are
// the binary contract -- a pointer to a vtable pointer, IUnknown in the first
// three slots -- and none of that needs Windows; see §8.5 of the spec. What is
// here is what does: starting a thread's apartment, asking the registry for an
// object, and freeing what one hands back.
//
// Declarations cost nothing, so this module needs no library on its own; a
// program that *calls* one of them wants `-l ole32`, or `Win32.Com`, which
// names it with a pragma.
module Win32.Ole32;

import Standard.Com;

#if WINDOWS

public extern "C" {
    // `CoInitializeEx` returns S_OK the first time on a thread and S_FALSE
    // afterwards; both mean the apartment is up, and both must be matched by a
    // `CoUninitialize`.
    int  CoInitializeEx(byte* reserved, uint model);
    void CoUninitialize();

    // The registry-driven constructor. `result` is where the new object's
    // interface pointer goes, already at +1.
    int  CoCreateInstance(Guid* classId, byte* outer, uint context,
                          Guid* interfaceId, byte** result);

    // The allocator every COM out-parameter that is not an interface comes
    // from: a string, a struct, an array of any of them.
    byte* CoTaskMemAlloc(nuint size);
    void  CoTaskMemFree(byte* block);

    // GUIDs as text and back, which is how a CLSID reaches a program that has
    // no header to take it from.
    int  CLSIDFromString(char16* text, Guid* classId);
    int  IIDFromString(char16* text, Guid* interfaceId);
    int  StringFromGUID2(Guid* value, char16* buffer, int capacity);
}

// ------------------------------------------------------------- apartments

/// One thread, one object at a time; calls from elsewhere are marshalled
/// through a message queue. Anything that puts up a window wants this, the
/// shell's dialogs included.
public const uint ApartmentThreaded = 0x2u;

/// Any thread, any time. The object is responsible for its own locking.
public const uint MultiThreaded = 0x0u;

/// Do not let OLE1 clients in. Modern code passes it and forgets it.
public const uint DisableOle1Dde = 0x4u;

/// Optimise for speed over memory, which is what every current sample passes.
public const uint SpeedOverMemory = 0x8u;

// ------------------------------------------------------------- CLSCTX

/// A DLL loaded into this process. The fast case, and what the shell uses.
public const uint InProcessServer = 0x1u;

/// A DLL that runs in the surrogate process.
public const uint InProcessHandler = 0x2u;

/// A separate process on this machine.
public const uint LocalServer = 0x4u;

/// A different machine, which needs DCOM configured and is here for
/// completeness rather than for use.
public const uint RemoteServer = 0x10u;

/// In process or out, whichever is registered. The usual argument.
public const uint AllContexts = 0x17u;

// --------------------------------------------------------------- HRESULT

/// It worked.
public const int Ok = 0;

/// It worked, and the answer was the second of two: `CoInitializeEx` on a
/// thread whose apartment was already up, an enumerator that ran out early.
/// Success, and worth telling apart.
public const int False = 1;

/// The object does not implement the interface that was asked for.
public const int NoInterface = 0x80004002;

/// A null pointer where one was required.
public const int PointerError = 0x80004003;

/// The call was refused, or the user cancelled the dialog that was showing.
public const int Aborted = 0x80004004;

/// Nothing about the failure is specific.
public const int Failure = 0x80004005;

/// The operation is not implemented at all.
public const int NotImplemented = 0x80004001;

/// Out of memory.
public const int OutOfMemory = 0x8007000E;

/// One of the arguments was wrong.
public const int InvalidArgument = 0x80070057;

/// `HRESULT_FROM_WIN32(ERROR_CANCELLED)`: what a file dialog returns when the
/// user closed it without choosing anything. Not an error, and the one code a
/// caller of `IFileDialog.Show` has to tell apart from the rest.
public const int Cancelled = 0x800704C7;

/// Nothing was found where something was looked for.
public const int NotFound = 0x80070490;

#endif
