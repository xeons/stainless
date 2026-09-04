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

// kernel32: files, handles, memory, modules, environment and the system.
//
// Nothing here needs a `-l`. kernel32 is pulled in by the C runtime every
// Windows program already links, so these declarations resolve on their own —
// unlike `Win32.User` and its siblings, which each name the library they need.
module Win32.Kernel;

#if WINDOWS

import Win32;
import Standard.Collections;

// ================================================================== handles

public extern "C" {
    int   CloseHandle(void* handle);
    int   DuplicateHandle(void* sourceProcess, void* source, void* targetProcess,
                          void** target, uint access, int inheritable, uint options);
    int   SetHandleInformation(void* handle, uint mask, uint flags);
    int   GetHandleInformation(void* handle, uint* flags);
}

public const uint HandleFlagInherit = 0x00000001u;
public const uint DuplicateSameAccess = 0x00000002u;
public const uint DuplicateCloseSource = 0x00000001u;

/// Passed where a Win32 function takes a `SECURITY_ATTRIBUTES*`. Pass `null`
/// for the default, which is what almost every call wants; the one common
/// reason to build one is `InheritHandle`, which a child process needs.
public struct SecurityAttributes {
    public uint  Length;
    public void* Descriptor;
    public int   InheritHandle;
}

/// A `SECURITY_ATTRIBUTES` that says only "the child may inherit this handle".
public SecurityAttributes Inheritable() {
    SecurityAttributes attributes;
    attributes.Length = (uint)sizeof(SecurityAttributes);
    attributes.Descriptor = null;
    attributes.InheritHandle = 1;
    return attributes;
}

// ==================================================================== files

public extern "C" {
    void* CreateFileW(ushort* name, uint access, uint shareMode,
                      SecurityAttributes* security, uint disposition,
                      uint flags, void* template);
    int   ReadFile(void* file, void* buffer, uint toRead, uint* read, void* overlapped);
    int   WriteFile(void* file, void* buffer, uint toWrite, uint* written, void* overlapped);
    int   FlushFileBuffers(void* file);
    int   SetFilePointerEx(void* file, long distance, long* newPosition, uint origin);
    int   GetFileSizeEx(void* file, long* size);
    int   SetEndOfFile(void* file);

    int   DeleteFileW(ushort* name);
    int   CopyFileW(ushort* from, ushort* to, int failIfExists);
    int   MoveFileExW(ushort* from, ushort* to, uint flags);
    int   CreateDirectoryW(ushort* path, SecurityAttributes* security);
    int   RemoveDirectoryW(ushort* path);
    uint  GetFileAttributesW(ushort* path);
    int   SetFileAttributesW(ushort* path, uint attributes);

    uint  GetFullPathNameW(ushort* name, uint size, ushort* buffer, ushort** filePart);
    uint  GetTempPathW(uint size, ushort* buffer);
    uint  GetTempFileNameW(ushort* path, ushort* prefix, uint unique, ushort* buffer);
    uint  GetLongPathNameW(ushort* shortPath, ushort* buffer, uint size);
    uint  GetShortPathNameW(ushort* longPath, ushort* buffer, uint size);
}

/// What a handle may be used for. These are the generic rights; the specific
/// ones exist too, but a program that needs `FILE_WRITE_ATTRIBUTES` by name is
/// past the point where a binding helps.
public const uint GenericRead    = 0x80000000u;
public const uint GenericWrite   = 0x40000000u;
public const uint GenericExecute = 0x20000000u;
public const uint GenericAll     = 0x10000000u;
public const uint Delete         = 0x00010000u;
public const uint Synchronize    = 0x00100000u;

/// What other openers may do while this handle is open. Zero is exclusive.
public const uint FileShareRead   = 0x00000001u;
public const uint FileShareWrite  = 0x00000002u;
public const uint FileShareDelete = 0x00000004u;

/// `CreateFileW`'s disposition: what to do about the file already being there.
public const uint CreateNew        = 1u;
public const uint CreateAlways     = 2u;
public const uint OpenExisting     = 3u;
public const uint OpenAlways       = 4u;
public const uint TruncateExisting = 5u;

public const uint FileAttributeReadOnly   = 0x00000001u;
public const uint FileAttributeHidden     = 0x00000002u;
public const uint FileAttributeSystem     = 0x00000004u;
public const uint FileAttributeDirectory  = 0x00000010u;
public const uint FileAttributeArchive    = 0x00000020u;
public const uint FileAttributeNormal     = 0x00000080u;
public const uint FileAttributeTemporary  = 0x00000100u;
public const uint FileAttributeReparsePoint = 0x00000400u;
public const uint FileAttributeCompressed = 0x00000800u;
public const uint FileAttributeOffline    = 0x00001000u;
public const uint FileAttributeEncrypted  = 0x00004000u;

/// What `GetFileAttributesW` returns when it fails, which is not zero.
public const uint InvalidFileAttributes = 0xFFFFFFFFu;

public const uint FileFlagWriteThrough  = 0x80000000u;
public const uint FileFlagOverlapped    = 0x40000000u;
public const uint FileFlagNoBuffering   = 0x20000000u;
public const uint FileFlagRandomAccess  = 0x10000000u;
public const uint FileFlagSequentialScan = 0x08000000u;
public const uint FileFlagDeleteOnClose = 0x04000000u;
public const uint FileFlagBackupSemantics = 0x02000000u;

/// `SetFilePointerEx`'s origin.
public const uint FileBegin   = 0u;
public const uint FileCurrent = 1u;
public const uint FileEnd     = 2u;

public const uint MoveFileReplaceExisting = 0x00000001u;
public const uint MoveFileCopyAllowed     = 0x00000002u;
public const uint MoveFileWriteThrough    = 0x00000008u;

/// Opens or creates a file, taking the path as text.
///
/// Returns `InvalidHandle()` on failure — not null — and the reason is in
/// `Win32.LastError()`. This is the one place the two failure conventions are
/// most often confused, so `Win32.IsInvalid` covers both.
public void* OpenFile(String path, uint access, uint shareMode, uint disposition) {
    return CreateFileW(path.ToUtf16().ToPointer(), access, shareMode, null,
                       disposition, FileAttributeNormal, null);
}

/// True when something exists at this path, of any kind.
public bool Exists(String path) {
    return GetFileAttributesW(path.ToUtf16().ToPointer()) != InvalidFileAttributes;
}

/// True when the path names a directory. False when it names a file *and* when
/// there is nothing there, so it is not the negation of a file test.
public bool IsDirectory(String path) {
    uint attributes = GetFileAttributesW(path.ToUtf16().ToPointer());
    if (attributes == InvalidFileAttributes) { return false; }
    return (attributes & FileAttributeDirectory) != 0u;
}

/// The path with `.`, `..` and a relative prefix resolved against the current
/// directory. Windows does this textually; it does not touch the filesystem.
public String FullPath(String path) {
    var buffer = new WideBuffer(32768u);
    uint units = GetFullPathNameW(path.ToUtf16().ToPointer(), buffer.Capacity(),
                                  buffer.Pointer(), null);
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

/// The directory Windows hands out for temporary files, with its trailing
/// separator, which Windows includes and callers routinely forget.
public String TempPath() {
    var buffer = new WideBuffer(32768u);
    uint units = GetTempPathW(buffer.Capacity(), buffer.Pointer());
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

// ================================================================ directories

/// One entry from a directory walk.
///
/// `WIN32_FIND_DATAW` ends in two inline `WCHAR` arrays, and Stainless has no
/// inline fixed-size array field, so this owns the 592 bytes as a block and
/// reads the fields out of it at the offsets the header gives. That is why this
/// is a class with accessors rather than a `struct` with fields: the struct
/// could not be declared with the right size, and one with the wrong size would
/// be handed to Windows to overrun.
public class FindData {
    void* block;

    public FindData() {
        block = malloc(592u);
        if (block == null) { sl_fail("out of memory allocating a WIN32_FIND_DATAW"); }
    }

    ~FindData() { free(block); }

    /// The block itself, to hand to `FindFirstFileW` or `FindNextFileW`.
    public void* Pointer() { return block; }

    /// `dwFileAttributes`, at offset 0.
    public uint Attributes() { return *(uint*)((byte*)block + 0u); }

    /// `ftCreationTime`, `ftLastAccessTime` and `ftLastWriteTime`, each a
    /// `FILETIME` — 100-nanosecond ticks since 1601 — at offsets 4, 12 and 20.
    public ulong Created()  { return ReadFileTime(4u); }
    public ulong Accessed() { return ReadFileTime(12u); }
    public ulong Written()  { return ReadFileTime(20u); }

    /// `nFileSizeHigh` and `nFileSizeLow`, at 28 and 32, joined the way the
    /// header intends them to be.
    public ulong Size() {
        ulong high = (ulong)(*(uint*)((byte*)block + 28u));
        ulong low  = (ulong)(*(uint*)((byte*)block + 32u));
        return (high << 32) | low;
    }

    /// `cFileName`, at offset 44: the name alone, never a path.
    public String Name() {
        return Text.FromNullTerminatedUtf16((ushort*)((byte*)block + 44u));
    }

    public bool IsDirectory() { return (Attributes() & FileAttributeDirectory) != 0u; }

    /// True for `.` and `..`, which a directory walk always sees first and
    /// which almost no caller wants.
    public bool IsSelfOrParent() {
        var name = Name();
        return name == "." || name == "..";
    }

    /// A `FILETIME` is two 32-bit halves and is not 8-aligned inside this
    /// struct, so it is read as halves rather than as one `ulong`.
    ulong ReadFileTime(nuint offset) {
        ulong low  = (ulong)(*(uint*)((byte*)block + offset));
        ulong high = (ulong)(*(uint*)((byte*)block + offset + 4u));
        return (high << 32) | low;
    }
}

public extern "C" {
    void* FindFirstFileW(ushort* pattern, void* data);
    int   FindNextFileW(void* find, void* data);
    int   FindClose(void* find);
}

// This module's own plumbing rather than part of the Win32 surface, so it stays
// private: a consumer reaching for `malloc` should say so itself.
extern "C" {
    void* malloc(nuint size);
    void  free(void* block);
    void  sl_fail(byte* message);
}

/// Begins a directory walk. `pattern` is a path with wildcards — `C:\dir\*` —
/// not a directory. Returns `InvalidHandle()` when nothing matches, with
/// `ERROR_FILE_NOT_FOUND`.
public void* FindFirst(String pattern, FindData data) {
    return FindFirstFileW(pattern.ToUtf16().ToPointer(), data.Pointer());
}

/// The next entry, or false at the end — where `Win32.LastError()` is
/// `ErrorNoMoreFiles` rather than a real failure.
public bool FindNext(void* find, FindData data) {
    return Win32.Succeeded(FindNextFileW(find, data.Pointer()));
}

/// Every name in a directory, without `.` and `..`.
///
/// The whole walk in one call, for the common case where the caller wants a
/// list rather than a cursor. It returns names, not paths.
public List<String> Entries(String directory) {
    var names = new List<String>();
    var data = new FindData();

    void* find = FindFirst(directory + "\\*", data);
    if (Win32.IsInvalid(find)) { return names; }

    // FindFirstFileW has already produced the first entry, so this reads
    // before it advances rather than after.
    bool more = true;
    while (more) {
        if (!data.IsSelfOrParent()) { names.Add(data.Name()); }
        more = FindNext(find, data);
    }

    FindClose(find);
    return names;
}

// =================================================================== memory

public extern "C" {
    void* VirtualAlloc(void* at, nuint size, uint type, uint protect);
    int   VirtualFree(void* at, nuint size, uint type);
    int   VirtualProtect(void* at, nuint size, uint protect, uint* previous);

    void* GetProcessHeap();
    void* HeapAlloc(void* heap, uint flags, nuint size);
    void* HeapReAlloc(void* heap, uint flags, void* block, nuint size);
    int   HeapFree(void* heap, uint flags, void* block);
    nuint HeapSize(void* heap, uint flags, void* block);

    void* LocalFree(void* block);
    void* GlobalAlloc(uint flags, nuint size);
    void* GlobalLock(void* block);
    int   GlobalUnlock(void* block);
    void* GlobalFree(void* block);
}

public const uint MemCommit  = 0x00001000u;
public const uint MemReserve = 0x00002000u;
public const uint MemReset   = 0x00080000u;
public const uint MemRelease = 0x00008000u;
public const uint MemDecommit = 0x00004000u;

public const uint PageNoAccess         = 0x01u;
public const uint PageReadOnly         = 0x02u;
public const uint PageReadWrite        = 0x04u;
public const uint PageWriteCopy        = 0x08u;
public const uint PageExecute          = 0x10u;
public const uint PageExecuteRead      = 0x20u;
public const uint PageExecuteReadWrite = 0x40u;
public const uint PageGuard            = 0x100u;

public const uint HeapZeroMemory = 0x00000008u;

/// `GMEM_MOVEABLE`, which is what the clipboard requires of anything handed to
/// it. See `Win32.User.SetClipboardText`.
public const uint GlobalMoveable = 0x0002u;
public const uint GlobalFixed    = 0x0000u;
public const uint GlobalZeroInit = 0x0040u;

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

public extern "C" {
    void* LoadLibraryW(ushort* name);
    void* LoadLibraryExW(ushort* name, void* reserved, uint flags);
    int   FreeLibrary(void* library);
    void* GetProcAddress(void* library, byte* name);
    void* GetModuleHandleW(ushort* name);
    uint  GetModuleFileNameW(void* library, ushort* buffer, uint size);
}

public const uint LoadLibrarySearchSystem32 = 0x00000800u;
public const uint LoadLibraryAsDataFile     = 0x00000002u;

/// Loads a DLL by name or path, or null on failure.
///
/// `GetProcAddress` takes an *ANSI* name even in a wide program, because an
/// export name is bytes in the file rather than text — which is why its binding
/// takes a `byte*` and a Stainless string literal reaches it directly.
public void* LoadLibrary(String name) {
    return LoadLibraryW(name.ToUtf16().ToPointer());
}

/// The full path of the running .exe, or of a loaded DLL when given its handle.
public String ModulePath(void* library) {
    var buffer = new WideBuffer(32768u);
    uint units = GetModuleFileNameW(library, buffer.Pointer(), buffer.Capacity());
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

/// The full path of the running executable.
public String ExecutablePath() { return ModulePath(null); }

// ============================================================== environment

public extern "C" {
    uint  GetEnvironmentVariableW(ushort* name, ushort* buffer, uint size);
    int   SetEnvironmentVariableW(ushort* name, ushort* value);
    uint  ExpandEnvironmentStringsW(ushort* source, ushort* buffer, uint size);
    ushort* GetCommandLineW();
    uint  GetCurrentDirectoryW(uint size, ushort* buffer);
    int   SetCurrentDirectoryW(ushort* path);
    uint  GetSystemDirectoryW(ushort* buffer, uint size);
    uint  GetWindowsDirectoryW(ushort* buffer, uint size);
    int   GetComputerNameW(ushort* buffer, uint* size);
}

/// An environment variable's value, or an empty string when it is not set.
///
/// The two are told apart with `Win32.LastError()`, which is
/// `ErrorEnvvarNotFound` (203) for the second — a distinction that matters
/// rarely enough not to be worth a `Result` here.
public String Environment(String name) {
    var buffer = new WideBuffer(32768u);
    uint units = GetEnvironmentVariableW(name.ToUtf16().ToPointer(),
                                         buffer.Pointer(), buffer.Capacity());
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

/// Sets a variable for this process and the children it starts after this
/// point. It does not reach the parent, and it is not persistent.
public bool SetEnvironment(String name, String value) {
    return Win32.Succeeded(SetEnvironmentVariableW(name.ToUtf16().ToPointer(),
                                                   value.ToUtf16().ToPointer()));
}

/// Removes a variable from this process's environment.
public bool ClearEnvironment(String name) {
    return Win32.Succeeded(SetEnvironmentVariableW(name.ToUtf16().ToPointer(), null));
}

/// `%TEMP%\log.txt` with the variables filled in.
public String Expand(String text) {
    var buffer = new WideBuffer(32768u);
    uint units = ExpandEnvironmentStringsW(text.ToUtf16().ToPointer(),
                                           buffer.Pointer(), buffer.Capacity());
    if (units == 0u) { return ""; }

    // This one counts the terminator, unlike its neighbours.
    return Text.FromUtf16(buffer.Pointer(), (nuint)(units - 1u));
}

/// The whole command line as one string, exactly as Windows keeps it —
/// unsplit, and including the program name.
public String CommandLine() {
    return Text.FromNullTerminatedUtf16(GetCommandLineW());
}

public String CurrentDirectory() {
    var buffer = new WideBuffer(32768u);
    uint units = GetCurrentDirectoryW(buffer.Capacity(), buffer.Pointer());
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

public bool SetCurrentDirectory(String path) {
    return Win32.Succeeded(SetCurrentDirectoryW(path.ToUtf16().ToPointer()));
}

public String SystemDirectory() {
    var buffer = new WideBuffer(32768u);
    uint units = GetSystemDirectoryW(buffer.Pointer(), buffer.Capacity());
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

public String WindowsDirectory() {
    var buffer = new WideBuffer(32768u);
    uint units = GetWindowsDirectoryW(buffer.Pointer(), buffer.Capacity());
    if (units == 0u) { return ""; }
    return buffer.Text(units);
}

/// The NetBIOS name of this machine, which is at most 15 characters.
public String ComputerName() {
    var buffer = new WideBuffer(256u);
    uint size = buffer.Capacity();
    if (!Win32.Succeeded(GetComputerNameW(buffer.Pointer(), &size))) { return ""; }
    return buffer.Text(size);
}

// =================================================================== system

/// `SYSTEM_INFO`. The leading union is a historical accident the header still
/// carries: the whole word was `dwOemId` on Windows NT, and is now an
/// architecture and a reserved half.
public struct ProcessorId {
    public ushort Architecture;
    public ushort Reserved;
}

public union OemId {
    public uint        Whole;
    public ProcessorId Split;
}

public struct SystemInfo {
    public OemId Processor;
    public uint  PageSize;
    public void* MinimumApplicationAddress;
    public void* MaximumApplicationAddress;
    public nuint ActiveProcessorMask;
    public uint  ProcessorCount;
    public uint  ProcessorType;
    public uint  AllocationGranularity;
    public ushort ProcessorLevel;
    public ushort ProcessorRevision;
}

public const ushort ProcessorArchitectureX64   = 9u;
public const ushort ProcessorArchitectureArm   = 5u;
public const ushort ProcessorArchitectureArm64 = 12u;
public const ushort ProcessorArchitectureX86   = 0u;

/// `MEMORYSTATUSEX`. `Length` must be set to `sizeof` before the call, which
/// `MemoryStatus()` does.
public struct MemoryStatus {
    public uint  Length;
    public uint  MemoryLoad;
    public ulong TotalPhysical;
    public ulong AvailablePhysical;
    public ulong TotalPageFile;
    public ulong AvailablePageFile;
    public ulong TotalVirtual;
    public ulong AvailableVirtual;
    public ulong AvailableExtendedVirtual;
}

public extern "C" {
    void GetSystemInfo(SystemInfo* info);
    void GetNativeSystemInfo(SystemInfo* info);
    int  GlobalMemoryStatusEx(MemoryStatus* status);
    void OutputDebugStringW(ushort* text);
    int  Beep(uint frequency, uint duration);
    int  IsDebuggerPresent();
}

/// Page size, processor count and the rest, as the running process sees it.
/// Under WOW64 that is the emulated view; `NativeSystem()` is the real one.
public SystemInfo System() {
    SystemInfo info;
    GetSystemInfo(&info);
    return info;
}

public SystemInfo NativeSystem() {
    SystemInfo info;
    GetNativeSystemInfo(&info);
    return info;
}

/// How much memory there is and how much is free. The `Length` field is
/// filled in here, because the call fails without it.
public MemoryStatus Memory() {
    MemoryStatus status;
    status.Length = (uint)sizeof(MemoryStatus);
    GlobalMemoryStatusEx(&status);
    return status;
}

/// Writes to the debugger's output window, and nowhere at all when no debugger
/// is attached.
public void DebugPrint(String text) {
    OutputDebugStringW(text.ToUtf16().ToPointer());
}

// ============================================================ process, thread

public extern "C" {
    void* GetCurrentProcess();
    uint  GetCurrentProcessId();
    void* GetCurrentThread();
    uint  GetCurrentThreadId();
    void  ExitProcess(uint code);
    void  Sleep(uint milliseconds);
    uint  SleepEx(uint milliseconds, int alertable);
    uint  WaitForSingleObject(void* handle, uint milliseconds);
    uint  WaitForMultipleObjects(uint count, void** handles, int all, uint milliseconds);
    void* OpenProcess(uint access, int inheritable, uint processId);
    int   GetExitCodeProcess(void* process, uint* code);
    int   TerminateProcess(void* process, uint code);
    int   SetPriorityClass(void* process, uint priority);
    uint  GetPriorityClass(void* process);
}

/// `WaitForSingleObject`'s answers. `WaitObject0` is the one that means the
/// thing became signalled; the others are all "no".
public const uint WaitObject0   = 0x00000000u;
public const uint WaitAbandoned = 0x00000080u;
public const uint WaitTimeout   = 0x00000102u;
public const uint WaitFailed    = 0xFFFFFFFFu;

/// Wait forever, which is what `INFINITE` is.
public const uint Infinite = 0xFFFFFFFFu;

public const uint ProcessAllAccess     = 0x001FFFFFu;
public const uint ProcessQueryInformation = 0x00000400u;
public const uint ProcessTerminate     = 0x00000001u;
public const uint ProcessVmRead        = 0x00000010u;
public const uint SynchronizeAccess    = 0x00100000u;

public const uint IdlePriorityClass     = 0x00000040u;
public const uint BelowNormalPriorityClass = 0x00004000u;
public const uint NormalPriorityClass   = 0x00000020u;
public const uint AboveNormalPriorityClass = 0x00008000u;
public const uint HighPriorityClass     = 0x00000080u;
public const uint RealtimePriorityClass = 0x00000100u;

/// Blocks until the handle is signalled, and answers whether it was.
///
/// A process handle becomes signalled when the process exits, a thread's when
/// the thread does, and an event's when it is set — which is why one function
/// covers all three.
public bool Wait(void* handle, uint milliseconds) {
    return WaitForSingleObject(handle, milliseconds) == WaitObject0;
}

#endif
