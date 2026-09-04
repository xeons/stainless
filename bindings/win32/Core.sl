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

// The Win32 API, declared rather than wrapped.
//
// This module is the vocabulary the rest of `Win32.*` is written in: the
// handle, the BOOL, the error code, and the buffer a wide API writes into.
// Everything here and in its sibling modules is Windows-only, and the whole
// file is `#if WINDOWS`, so on any other platform these modules exist and are
// empty rather than failing to build.
//
// **These are not part of the standard library**, and are compiled only by a
// program that asks for them:
//
// ```
// stainless build app.sl bindings/win32 -l user32
// ```
//
// The reason is the linker rather than taste. A library is searched only for
// symbols something refers to, but an undefined symbol is an error before the
// dead-strip that would have removed it: a wrapper here that calls
// `CreateWindowExW` makes every program that compiles this file need
// `user32.lib`, whether or not it ever creates a window. Keeping the bindings
// out of the always-compiled library keeps that cost with the programs that
// chose it.
//
// **Nothing is marshalled.** A `WNDCLASSEXW` is a Stainless `struct` with the
// same fields in the same order, and `sizeof` returns what C's does; a
// `WNDPROC` is a `delegate`, which is a bare function pointer. Stainless
// already speaks the platform C ABI, so a binding is a declaration and not a
// layer. What these modules add on top is the handful of places where saying it
// in Stainless is genuinely better than saying it in C: text, which crosses as
// UTF-8 and has to be widened, and lifetime, which a destructor can hold.
//
// Only the wide (`...W`) entry points are bound. The ANSI ones lose characters
// the user's filesystem is entitled to contain, and there is no reason to offer
// a way to do that.
module Win32;

#if WINDOWS

extern "C" {
    // The runtime's own abort, used for the one failure a constructor cannot
    // report: it prints the message and does not return.
    void  sl_fail(byte* message);

    uint  GetLastError();
    void  SetLastError(uint code);
    uint  FormatMessageW(uint flags, void* source, uint messageId, uint languageId,
                         ushort* buffer, uint size, void* arguments);

    void* malloc(nuint size);
    void  free(void* block);
}

// ------------------------------------------------------------------- errors

/// Ask `FormatMessageW` for the system's own table.
public const uint FormatMessageFromSystem = 0x00001000u;

/// Ignore any inserts in the message rather than expecting arguments for them.
public const uint FormatMessageIgnoreInserts = 0x00000200u;

public const uint ErrorSuccess           = 0u;
public const uint ErrorFileNotFound      = 2u;
public const uint ErrorPathNotFound      = 3u;
public const uint ErrorAccessDenied      = 5u;
public const uint ErrorInvalidHandle     = 6u;
public const uint ErrorNotEnoughMemory   = 8u;
public const uint ErrorInvalidData       = 13u;
public const uint ErrorNoMoreFiles       = 18u;
public const uint ErrorNotReady          = 21u;
public const uint ErrorSharingViolation  = 32u;
public const uint ErrorHandleEof         = 38u;
public const uint ErrorFileExists        = 80u;
public const uint ErrorInvalidParameter  = 87u;
public const uint ErrorBrokenPipe        = 109u;
public const uint ErrorInsufficientBuffer = 122u;
public const uint ErrorAlreadyExists     = 183u;
public const uint ErrorMoreData          = 234u;
public const uint ErrorNoMoreItems       = 259u;
public const uint ErrorOperationAborted  = 995u;
public const uint ErrorIoPending         = 997u;

/// The calling thread's last error code, which is only meaningful after a call
/// that has just failed. Windows does not clear it on success, so reading it
/// after a call that worked reads whatever the last failure left behind.
public uint LastError() { return GetLastError(); }

/// Sets the calling thread's error code, which a program with its own
/// Win32-shaped entry points may want to do.
public void SetError(uint code) { SetLastError(code); }

/// What Windows says this error code means, in the system's language.
///
/// Returns an empty string for a code the system has no message for, which is
/// the honest answer: inventing "unknown error 1234" here would make it
/// impossible for the caller to tell that apart from a real message.
public String Describe(uint code) {
    var buffer = new WideBuffer(1024u);
    uint units = FormatMessageW(
        FormatMessageFromSystem | FormatMessageIgnoreInserts,
        null, code, 0u, buffer.Pointer(), 1024u, null);

    if (units == 0u) { return ""; }

    // The system's messages are punctuated for a message box and end in CR LF.
    while (units > 0u) {
        ushort last = buffer.Unit((uint)(units - 1u));
        if (last != 13u && last != 10u && last != 32u) { break; }
        units = (uint)(units - 1u);
    }

    return Text.FromUtf16(buffer.Pointer(), (nuint)units);
}

/// What went wrong with the call that just failed, as text.
public String LastErrorMessage() { return Describe(GetLastError()); }

// ------------------------------------------------------------------ handles

/// `INVALID_HANDLE_VALUE`: -1, and not the same thing as a null handle.
///
/// Which of the two a failing call returns is per-function and not guessable —
/// `CreateFileW` returns this one, `CreateFileMappingW` returns null — so both
/// tests exist and the binding for each function says which it means.
public void* InvalidHandle() { return (void*)(nuint)0xFFFFFFFFFFFFFFFFu; }

/// True when a handle is `INVALID_HANDLE_VALUE` or null, which between them
/// cover every failure a handle-returning call reports.
public bool IsInvalid(void* handle) { return handle == null || handle == InvalidHandle(); }

// --------------------------------------------------------------------- BOOL

/// Win32's `BOOL` is an `int`, and non-zero is success.
///
/// Worth spelling out because the exceptions are famous: `GetMessageW` returns
/// -1 for an error and 0 for `WM_QUIT`, so it is one of the calls this must not
/// be used on. Its own binding says so.
///
/// Not called `Ok`, which is taken: a bare `Ok(x)` builds a `Result`.
public bool Succeeded(int result) { return result != 0; }

/// The other half, for the reading that is usually the interesting one.
public bool Failed(int result) { return result == 0; }

// ------------------------------------------------------------------ buffers

/// A block of UTF-16 for a wide API to write into.
///
/// Almost every `...W` function that produces text does it this way: the caller
/// hands over a buffer and a capacity, and gets back a length or a request for
/// more room. This owns such a buffer and frees it when it dies, so the pattern
/// costs a `new` and nothing else.
///
/// ```
/// var buffer = new WideBuffer(260u);
/// uint units = GetModuleFileNameW(null, buffer.Pointer(), buffer.Capacity());
/// String path = buffer.Text(units);
/// ```
///
/// The block is one unit longer than its capacity and starts zeroed, so a
/// function that fills it completely without terminating still leaves a
/// terminator behind for `Text()` to find.
public class WideBuffer {
    ushort* units;
    uint    capacity;

    /// A buffer with room for `unitCount` UTF-16 units, not counting the
    /// terminator. Aborts if the allocation fails, as `new` does everywhere.
    public WideBuffer(uint unitCount) {
        capacity = unitCount;
        units = (ushort*)malloc(((nuint)unitCount + 1u) * 2u);
        if (units == null) { sl_fail("out of memory allocating a Win32 wide buffer"); }

        // Zeroed, so a caller that reads the buffer without checking the
        // returned length gets an empty string rather than whatever was there.
        for (nuint i = 0u; i <= (nuint)unitCount; i = i + 1u) { units[i] = 0u; }
    }

    ~WideBuffer() { free((void*)units); }

    /// The buffer itself, to hand to a wide API.
    public ushort* Pointer() { return units; }

    /// How many units fit, not counting the terminator. This is the number
    /// nearly every wide API wants as its size argument.
    public uint Capacity() { return capacity; }

    /// One unit, without a bounds check — this is a raw buffer and reading past
    /// the end is the caller's mistake to avoid, as it is in C.
    public ushort Unit(uint index) { return units[index]; }

    /// The first `unitCount` units as text.
    public String Text(uint unitCount) {
        return Text.FromUtf16(units, (nuint)unitCount);
    }

    /// Everything up to the first NUL, which is what a function that reports no
    /// length has left behind.
    public String Text() { return Text.FromNullTerminatedUtf16(units); }
}

/// A block of raw bytes for an API that writes binary rather than text.
///
/// The registry is the usual reason: a value can be a `REG_BINARY` or a
/// `REG_DWORD` as easily as a string, and the call that reads one wants
/// somewhere to put it.
public class ByteBuffer {
    byte* bytes;
    uint  capacity;

    public ByteBuffer(uint byteCount) {
        capacity = byteCount;
        bytes = (byte*)malloc((nuint)byteCount);
        if (bytes == null) { sl_fail("out of memory allocating a Win32 byte buffer"); }

        for (nuint i = 0u; i < (nuint)byteCount; i = i + 1u) { bytes[i] = 0u; }
    }

    ~ByteBuffer() { free((void*)bytes); }

    public byte* Pointer() { return bytes; }
    public uint Capacity() { return capacity; }

    /// One byte, unchecked.
    public byte At(uint index) { return bytes[index]; }

    /// The first four bytes as a `uint`, which is what a `REG_DWORD` is.
    public uint AsUInt() { return *(uint*)bytes; }

    /// The first eight bytes as a `ulong`, which is what a `REG_QWORD` is.
    public ulong AsULong() { return *(ulong*)bytes; }

    /// The bytes as UTF-16 text, up to the first NUL. `REG_SZ` is stored this
    /// way, and Windows counts its length in bytes rather than in units.
    public String AsText() { return Text.FromNullTerminatedUtf16((ushort*)bytes); }
}

#endif
