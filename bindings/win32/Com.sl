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

// Starting COM, asking it for an object, and reading what it hands back.
//
// A convenience layer over `Win32.Ole32`. It names ole32 itself with a pragma,
// so a program compiling it needs no `-l`.
//
// The language already owns the hard half. `com interface` is the binary
// contract and ARC drives AddRef and Release, so nothing here counts
// references and nothing here can leak one. What is left is the Windows half:
// an apartment, a class ID, and the allocator every COM out-parameter comes
// from.
module Win32.Com;

#if WINDOWS

// The library this module needs, so that a program compiling it does not
// have to repeat the name on its own command line.
#pragma comment(lib, "ole32")

import Standard.Com;
import Standard.Text;
import Win32;
import Win32.Ole32;

// ---------------------------------------------------------------- HRESULT

/// Whether an `HRESULT` says the call worked.
///
/// The sign bit is the whole test, which is why a success code can carry
/// information -- `S_FALSE` is 1 and means "yes, but the second answer".
public bool Succeeded(int result) { return result >= 0; }

/// Whether an `HRESULT` says the call did not work.
public bool Failed(int result) { return result < 0; }

/// Whether a failure is the user having closed a dialog rather than anything
/// going wrong.
public bool WasCancelled(int result) { return result == Cancelled; }

/// An `HRESULT` as text.
///
/// A COM error is often a Win32 code wrapped in `HRESULT_FROM_WIN32`, in which
/// case the message Windows already has for it is the useful one. Anything
/// else is reported as its hex code, because inventing prose for a facility
/// this does not know would be worse than showing the number.
public String Describe(int result) {
    if (result == Ok)              { return "ok"; }
    if (result == False)           { return "ok (second answer)"; }
    if (result == Cancelled)       { return "cancelled"; }
    if (result == NoInterface)     { return "no such interface"; }
    if (result == PointerError)    { return "null pointer"; }
    if (result == Aborted)         { return "aborted"; }
    if (result == OutOfMemory)     { return "out of memory"; }
    if (result == InvalidArgument) { return "invalid argument"; }
    if (result == NotImplemented)  { return "not implemented"; }
    if (result == NotFound)        { return "not found"; }
    if (result == Failure)         { return "unspecified failure"; }

    // HRESULT_FROM_WIN32(x) is 0x8007 in the high half and the code in the
    // low half, so Windows' own message is available for those.
    if ((result & 0xFFFF0000) == 0x80070000) {
        return Win32.Describe((uint)(result & 0x0000FFFF));
    }

    return "COM error 0x" + Hex((uint)result);
}

/// An unsigned value as eight hex digits, which is how an `HRESULT` is
/// written everywhere it appears.
String Hex(uint value) {
    var digits = "0123456789ABCDEF";
    var builder = new StringBuilder();

    for (int shift = 28; shift >= 0; shift = shift - 4) {
        nuint at = (nuint)((value >> (uint)shift) & 0xFu);
        builder.Append(digits.Substring(at, 1u));
    }
    return builder.ToText();
}

// -------------------------------------------------------------- apartments

/// Brings this thread's apartment up, single-threaded, which is what anything
/// that shows a window needs.
///
/// Every successful call must be matched by an `Uninitialize`, including the
/// ones that return `S_FALSE` because the apartment was already up. Reference
/// counting an apartment is Windows' rule, not this binding's.
public bool Initialize() {
    return Succeeded(CoInitializeEx(null, ApartmentThreaded | DisableOle1Dde));
}

/// Brings this thread's apartment up free-threaded, for a thread that will not
/// pump messages.
public bool InitializeMultiThreaded() {
    return Succeeded(CoInitializeEx(null, MultiThreaded | DisableOle1Dde));
}

/// Drops one of this thread's `Initialize` calls.
///
/// **Every COM reference must be gone before this runs**, and ARC drops one at
/// the end of the scope that holds it -- which is after this call, if the two
/// are in the same scope. Releasing an object whose apartment has been torn
/// down goes through a vtable that is no longer there.
///
/// In C the release and the `CoUninitialize` are both statements and the
/// programmer orders them. Here one of them is emitted, so what orders them is
/// the scope:
///
/// ```
/// Com.Initialize();
/// {
///     IFileOpenDialog dialog = ...;   // released when this block ends
/// }
/// Com.Uninitialize();                 // and only then does the apartment go
/// ```
///
/// The conveniences in `Win32.Dialogs` and `Win32.Shell` are safe either way:
/// each drops whatever it made before it returns, so nothing of theirs is
/// still alive when a caller uninitializes.
public void Uninitialize() { CoUninitialize(); }

// ------------------------------------------------------------------- GUIDs

/// A GUID written the way a registry entry or a header writes one.
///
/// Both `"{42f85136-db7e-439c-85f1-e4075d135fc8}"` and the same without braces
/// are accepted, because a CLSID is copied from a registry key as often as
/// from a header. A string that is not a GUID gives an all-zero one, which
/// matches no class and no interface.
///
/// This is how a CLSID reaches a program. An IID does not need it: `[Guid]` on
/// a `com interface` folds to a constant, and `iidof` is its address.
public Guid Parse(String text) {
    Guid value;

    // There is no StartsWith on String yet, and one character is all this
    // needs to know.
    String braced = text;
    if (text.IsEmpty() || text.Substring(0u, 1u) != "{") {
        braced = "{" + text + "}";
    }

    if (Failed(CLSIDFromString(braced.ToUtf16().ToPointer(), &value))) {
        Guid empty;
        return empty;
    }
    return value;
}

/// A GUID as `{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`.
public String Format(Guid value) {
    // 38 characters and a NUL, which is what StringFromGUID2 documents.
    var buffer = new WideBuffer(40u);
    int units = StringFromGUID2(&value, buffer.Pointer(), (int)buffer.Capacity());
    if (units <= 0) { return ""; }

    return Text.FromUtf16(buffer.Pointer(), (nuint)(units - 1));
}

// -------------------------------------------------------------- activation

/// Why an object could not be made.
public enum ComError : uint {
    None = 0u,

    /// No class with that CLSID is registered, or its server is missing.
    NotRegistered = 1u,

    /// The class exists and does not implement the interface asked for.
    NoInterface = 2u,

    /// COM was never started on this thread.
    NotInitialized = 3u,

    /// Something else. `Describe` on the raw code says what.
    Other = 4u,
}

/// Makes the object a CLSID names and asks it for one interface.
///
/// The pointer that comes back is at +1, and the caller adopts it with a cast:
///
/// ```
/// var made = Com.Create(Com.Parse(Dialogs.FileOpenDialogClsid), iidof(IFileOpenDialog));
/// if (made.IsOk()) {
///     IFileOpenDialog dialog = (IFileOpenDialog)made.Value();
///     ...                       // ARC releases it at the end of the scope
/// }
/// ```
///
/// The raw `byte*` rather than the interface itself is the boundary this
/// language does not cross on its own: which interface a caller asked for is
/// known to the caller and not to a signature, so the cast is where the
/// programmer says it.
public Result<byte*, ComError> Create(Guid classId, Guid* interfaceId) {
    byte* made = null;
    int hr = CoCreateInstance(&classId, null, AllContexts, interfaceId, &made);

    if (Succeeded(hr)) { return Ok(made); }
    return Fail(Classify(hr));
}

/// Makes an object in this process only, refusing a class that would need a
/// server started.
public Result<byte*, ComError> CreateInProcess(Guid classId, Guid* interfaceId) {
    byte* made = null;
    int hr = CoCreateInstance(&classId, null, InProcessServer, interfaceId, &made);

    if (Succeeded(hr)) { return Ok(made); }
    return Fail(Classify(hr));
}

/// An `HRESULT` from an activation call as one of the errors above.
public ComError Classify(int result) {
    if (Succeeded(result))                { return ComError.None; }
    if (result == NoInterface)            { return ComError.NoInterface; }
    if ((uint)result == 0x80040154u)      { return ComError.NotRegistered; }  // REGDB_E_CLASSNOTREG
    if ((uint)result == 0x800401F0u)      { return ComError.NotInitialized; } // CO_E_NOTINITIALIZED
    return ComError.Other;
}

// ------------------------------------------------------------- task memory

/// Reads a string a COM call wrote through a `char16**`, and frees it.
///
/// Almost every string COM returns is allocated with `CoTaskMemAlloc` and is
/// the caller's to release, which is the leak this exists to make impossible.
/// A null pointer reads as the empty string, because a call that failed leaves
/// the caller holding one.
public String TakeString(char16* text) {
    if (text == null) { return ""; }

    String result = Text.FromNullTerminatedUtf16(text);
    CoTaskMemFree((byte*)text);
    return result;
}

/// Frees a block COM allocated, for the cases `TakeString` does not cover.
public void Free(byte* block) { CoTaskMemFree(block); }

#endif
