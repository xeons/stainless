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

// The vocabulary the other `Win32.*` conveniences are written in: the `BOOL`,
// the handle, the error code as text, and the buffer a wide API writes into.
//
// Two layers live under `Win32.`, and the name says which is which:
//
//   Win32.Kernel32, Win32.User32, ...   a DLL name: declarations and nothing
//                                       else, spelled as Windows spells them
//   Win32, Win32.Files, Win32.Ui, ...   a task name: the conveniences, built
//                                       on those declarations
//
// Importing a raw module costs nothing and needs no `-l`, because a declaration
// nothing calls is not a reference. Importing one of these compiles code that
// *does* call, so it needs whatever library that DLL is.
module Win32;

#if WINDOWS

import Win32.Kernel32;
import Win32.Handles;

extern "C" {
    void* malloc(nuint size);
    void  free(void* block);

    // The runtime's own abort, for the one failure a constructor cannot
    // report: it prints the message and does not return.
    void  sl_fail(byte* message);
}

// ------------------------------------------------------------------- errors

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
        null, code, 0u, buffer.Pointer(), buffer.Capacity(), null);

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

/// True when a handle is `INVALID_HANDLE_VALUE` or null, which between them
/// cover every failure a handle-returning call reports.
///
/// Which of the two a given function uses is not guessable — `CreateFileW`
/// returns the first, `CreateWindowExW` the second — so this covers both.
public bool IsInvalid(HANDLE handle) { return handle == null || handle == InvalidHandle(); }

// --------------------------------------------------------------------- BOOL

/// Win32's `BOOL` is an `int`, and non-zero is success.
///
/// Worth spelling out because the exceptions are famous: `GetMessageW` returns
/// -1 for an error and 0 for `WM_QUIT`, so it is one of the calls this must not
/// be used on — `Win32.Ui.RunMessageLoop` is where that is handled.
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
    char16* units;
    uint    capacity;

    /// A buffer with room for `unitCount` UTF-16 units, not counting the
    /// terminator. Aborts if the allocation fails, as `new` does everywhere.
    public WideBuffer(uint unitCount) {
        capacity = unitCount;
        units = (char16*)malloc(((nuint)unitCount + 1u) * 2u);
        if (units == null) { sl_fail("out of memory allocating a Win32 wide buffer"); }

        // Zeroed, so a caller that reads the buffer without checking the
        // returned length gets an empty string rather than whatever was there.
        for (nuint i = 0u; i <= (nuint)unitCount; i = i + 1u) { units[i] = 0u; }
    }

    ~WideBuffer() { free((void*)units); }

    /// The buffer itself, to hand to a wide API.
    public char16* Pointer() { return units; }

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
    public String AsText() { return Text.FromNullTerminatedUtf16((char16*)bytes); }
}

/// Copies text into a buffer the caller owns, NUL terminated.
///
/// Two APIs need this rather than `ToUtf16().ToPointer()`: `CreateProcessW`,
/// which may *write to* the command line it is given, and the clipboard, which
/// takes ownership of the block it is handed.
public WideBuffer Copy(String text) {
    var wide = text.ToUtf16();
    var buffer = new WideBuffer((uint)wide.UnitCount());

    char16* target = buffer.Pointer();
    char16* source = wide.ToPointer();
    for (nuint i = 0u; i < wide.UnitCount(); i = i + 1u) { target[i] = source[i]; }
    return buffer;
}

#endif
