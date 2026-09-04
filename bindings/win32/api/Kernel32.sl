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

// kernel32.dll, declared and nothing else.
//
// This is a raw binding: entry points, structs, unions and constants, with the
// names Windows gives them, so that anything found on MSDN is here under the
// same spelling. There are no conveniences — those are in `Win32` and its
// task-named siblings, which are built on this.
//
// Nothing here needs a `-l`. kernel32 is pulled in by the C runtime every
// Windows program already links.
module Win32.Kernel32;

#if WINDOWS

// =================================================================== errors

public extern "C" {
    uint GetLastError();
    void SetLastError(uint code);
    uint FormatMessageW(uint flags, void* source, uint messageId, uint languageId,
                        ushort* buffer, uint size, void* arguments);
}

public const uint FormatMessageFromSystem     = 0x00001000u;
public const uint FormatMessageIgnoreInserts  = 0x00000200u;
public const uint FormatMessageAllocateBuffer = 0x00000100u;
public const uint FormatMessageFromString     = 0x00000400u;
public const uint FormatMessageFromHModule    = 0x00000800u;

public const uint ErrorSuccess            = 0u;
public const uint ErrorFileNotFound       = 2u;
public const uint ErrorPathNotFound       = 3u;
public const uint ErrorAccessDenied       = 5u;
public const uint ErrorInvalidHandle      = 6u;
public const uint ErrorNotEnoughMemory    = 8u;
public const uint ErrorInvalidData        = 13u;
public const uint ErrorNoMoreFiles        = 18u;
public const uint ErrorNotReady           = 21u;
public const uint ErrorSharingViolation   = 32u;
public const uint ErrorHandleEof          = 38u;
public const uint ErrorFileExists         = 80u;
public const uint ErrorInvalidParameter   = 87u;
public const uint ErrorBrokenPipe         = 109u;
public const uint ErrorInsufficientBuffer = 122u;
public const uint ErrorAlreadyExists      = 183u;
public const uint ErrorEnvvarNotFound     = 203u;
public const uint ErrorMoreData           = 234u;
public const uint ErrorNoMoreItems        = 259u;
public const uint ErrorOperationAborted   = 995u;
public const uint ErrorIoPending          = 997u;

// ================================================================== handles

public extern "C" {
    int CloseHandle(void* handle);
    int DuplicateHandle(void* sourceProcess, void* source, void* targetProcess,
                        void** target, uint access, int inheritable, uint options);
    int SetHandleInformation(void* handle, uint mask, uint flags);
    int GetHandleInformation(void* handle, uint* flags);
}

public const uint HandleFlagInherit        = 0x00000001u;
public const uint HandleFlagProtectFromClose = 0x00000002u;
public const uint DuplicateCloseSource     = 0x00000001u;
public const uint DuplicateSameAccess      = 0x00000002u;

/// `INVALID_HANDLE_VALUE`: -1, and not the same thing as a null handle.
///
/// Which of the two a failing call returns is per-function and not guessable —
/// `CreateFileW` returns this one, `CreateFileMappingW` returns null. A
/// function rather than a `const` because Stainless has no `const void*`.
public void* InvalidHandle() { return (void*)(nuint)0xFFFFFFFFFFFFFFFFu; }

/// `SECURITY_ATTRIBUTES`. Pass `null` where a call takes one and the default
/// will do, which is almost everywhere.
public struct SecurityAttributes {
    public uint  Length;
    public void* Descriptor;
    public int   InheritHandle;
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

    void* FindFirstFileW(ushort* pattern, void* data);
    int   FindNextFileW(void* find, void* data);
    int   FindClose(void* find);

    int   CreatePipe(void** read, void** write, SecurityAttributes* security, uint size);
    int   PeekNamedPipe(void* pipe, void* buffer, uint size, uint* read,
                        uint* available, uint* left);
}

/// The generic access rights. The specific ones exist too, but a program that
/// needs `FILE_WRITE_ATTRIBUTES` by name is past the point where a binding
/// helps.
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

public const uint FileAttributeReadOnly      = 0x00000001u;
public const uint FileAttributeHidden        = 0x00000002u;
public const uint FileAttributeSystem        = 0x00000004u;
public const uint FileAttributeDirectory     = 0x00000010u;
public const uint FileAttributeArchive       = 0x00000020u;
public const uint FileAttributeNormal        = 0x00000080u;
public const uint FileAttributeTemporary     = 0x00000100u;
public const uint FileAttributeReparsePoint  = 0x00000400u;
public const uint FileAttributeCompressed    = 0x00000800u;
public const uint FileAttributeOffline       = 0x00001000u;
public const uint FileAttributeEncrypted     = 0x00004000u;

/// What `GetFileAttributesW` returns when it fails, which is not zero.
public const uint InvalidFileAttributes = 0xFFFFFFFFu;

public const uint FileFlagWriteThrough     = 0x80000000u;
public const uint FileFlagOverlapped       = 0x40000000u;
public const uint FileFlagNoBuffering      = 0x20000000u;
public const uint FileFlagRandomAccess     = 0x10000000u;
public const uint FileFlagSequentialScan   = 0x08000000u;
public const uint FileFlagDeleteOnClose    = 0x04000000u;
public const uint FileFlagBackupSemantics  = 0x02000000u;

/// `SetFilePointerEx`'s origin.
public const uint FileBegin   = 0u;
public const uint FileCurrent = 1u;
public const uint FileEnd     = 2u;

public const uint MoveFileReplaceExisting = 0x00000001u;
public const uint MoveFileCopyAllowed     = 0x00000002u;
public const uint MoveFileWriteThrough    = 0x00000008u;

/// The byte offsets of `WIN32_FIND_DATAW`'s fields, and its size.
///
/// It is not declared as a struct because it ends in two inline `WCHAR` arrays
/// and Stainless has no inline fixed-size array field. A struct with the wrong
/// size would be handed to Windows to overrun, so it is not written at all;
/// `Win32.Files.FindData` owns the block and reads it at these offsets.
public const nuint FindDataSize             = 592u;
public const nuint FindDataAttributes       = 0u;
public const nuint FindDataCreationTime     = 4u;
public const nuint FindDataLastAccessTime   = 12u;
public const nuint FindDataLastWriteTime    = 20u;
public const nuint FindDataFileSizeHigh     = 28u;
public const nuint FindDataFileSizeLow      = 32u;
public const nuint FindDataFileName         = 44u;
public const nuint FindDataAlternateName    = 564u;

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

    void* LocalAlloc(uint flags, nuint size);
    void* LocalFree(void* block);
    void* GlobalAlloc(uint flags, nuint size);
    void* GlobalLock(void* block);
    int   GlobalUnlock(void* block);
    void* GlobalFree(void* block);
}

public const uint MemCommit   = 0x00001000u;
public const uint MemReserve  = 0x00002000u;
public const uint MemDecommit = 0x00004000u;
public const uint MemRelease  = 0x00008000u;
public const uint MemReset    = 0x00080000u;

public const uint PageNoAccess         = 0x01u;
public const uint PageReadOnly         = 0x02u;
public const uint PageReadWrite        = 0x04u;
public const uint PageWriteCopy        = 0x08u;
public const uint PageExecute          = 0x10u;
public const uint PageExecuteRead      = 0x20u;
public const uint PageExecuteReadWrite = 0x40u;
public const uint PageGuard            = 0x100u;

public const uint HeapZeroMemory       = 0x00000008u;
public const uint HeapNoSerialize      = 0x00000001u;

/// `GMEM_MOVEABLE`, which is what the clipboard requires of anything handed
/// to it.
public const uint GlobalFixed    = 0x0000u;
public const uint GlobalMoveable = 0x0002u;
public const uint GlobalZeroInit = 0x0040u;

// ================================================================== modules

public extern "C" {
    void* LoadLibraryW(ushort* name);
    void* LoadLibraryExW(ushort* name, void* reserved, uint flags);
    int   FreeLibrary(void* library);
    void* GetProcAddress(void* library, byte* name);
    void* GetModuleHandleW(ushort* name);
    uint  GetModuleFileNameW(void* library, ushort* buffer, uint size);
}

public const uint LoadLibraryAsDataFile      = 0x00000002u;
public const uint LoadLibrarySearchSystem32  = 0x00000800u;
public const uint LoadLibrarySearchDefaultDirs = 0x00001000u;

// ============================================================== environment

public extern "C" {
    uint    GetEnvironmentVariableW(ushort* name, ushort* buffer, uint size);
    int     SetEnvironmentVariableW(ushort* name, ushort* value);
    uint    ExpandEnvironmentStringsW(ushort* source, ushort* buffer, uint size);
    ushort* GetEnvironmentStringsW();
    int     FreeEnvironmentStringsW(ushort* block);
    ushort* GetCommandLineW();
    uint    GetCurrentDirectoryW(uint size, ushort* buffer);
    int     SetCurrentDirectoryW(ushort* path);
    uint    GetSystemDirectoryW(ushort* buffer, uint size);
    uint    GetWindowsDirectoryW(ushort* buffer, uint size);
    int     GetComputerNameW(ushort* buffer, uint* size);
}

// =================================================================== system

/// `SYSTEM_INFO`'s leading union is a historical accident the header still
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
    public OemId  Processor;
    public uint   PageSize;
    public void*  MinimumApplicationAddress;
    public void*  MaximumApplicationAddress;
    public nuint  ActiveProcessorMask;
    public uint   ProcessorCount;
    public uint   ProcessorType;
    public uint   AllocationGranularity;
    public ushort ProcessorLevel;
    public ushort ProcessorRevision;
}

public const ushort ProcessorArchitectureX86   = 0u;
public const ushort ProcessorArchitectureArm   = 5u;
public const ushort ProcessorArchitectureX64   = 9u;
public const ushort ProcessorArchitectureArm64 = 12u;

/// `MEMORYSTATUSEX`. `Length` must be set to `sizeof` before the call.
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

// =========================================================== process, thread

/// `STARTUPINFOW`. `sizeof` is 104, and `Size` must be set to it.
public struct StartupInfo {
    public uint    Size;
    public ushort* Reserved;
    public ushort* Desktop;
    public ushort* Title;
    public uint    X;
    public uint    Y;
    public uint    XSize;
    public uint    YSize;
    public uint    XCountChars;
    public uint    YCountChars;
    public uint    FillAttribute;
    public uint    Flags;
    public ushort  ShowWindow;
    public ushort  Reserved2;
    public byte*   Reserved3;
    public void*   StandardInput;
    public void*   StandardOutput;
    public void*   StandardError;
}

/// `PROCESS_INFORMATION`. Both handles belong to the caller and both must be
/// closed, including the thread handle nobody wants.
public struct ProcessInformation {
    public void* Process;
    public void* Thread;
    public uint  ProcessId;
    public uint  ThreadId;
}

public extern "C" {
    int   CreateProcessW(ushort* application, ushort* commandLine,
                         SecurityAttributes* processSecurity,
                         SecurityAttributes* threadSecurity,
                         int inheritHandles, uint flags, void* environment,
                         ushort* currentDirectory,
                         StartupInfo* startup, ProcessInformation* information);
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

public const uint StartFlagUseShowWindow = 0x00000001u;
public const uint StartFlagUseStdHandles = 0x00000100u;

public const uint CreateSuspended          = 0x00000004u;
public const uint DetachedProcess          = 0x00000008u;
public const uint CreateNewConsole         = 0x00000010u;
public const uint CreateNewProcessGroup    = 0x00000200u;
public const uint CreateUnicodeEnvironment = 0x00000400u;
public const uint CreateNoWindow           = 0x08000000u;

/// `WaitForSingleObject`'s answers. `WaitObject0` is the one that means the
/// thing became signalled; the others are all "no".
public const uint WaitObject0   = 0x00000000u;
public const uint WaitAbandoned = 0x00000080u;
public const uint WaitTimeout   = 0x00000102u;
public const uint WaitFailed    = 0xFFFFFFFFu;

/// `INFINITE`.
public const uint Infinite = 0xFFFFFFFFu;

public const uint ProcessTerminate         = 0x00000001u;
public const uint ProcessVmRead            = 0x00000010u;
public const uint ProcessQueryInformation  = 0x00000400u;
public const uint SynchronizeAccess        = 0x00100000u;
public const uint ProcessAllAccess         = 0x001FFFFFu;

public const uint IdlePriorityClass        = 0x00000040u;
public const uint BelowNormalPriorityClass = 0x00004000u;
public const uint NormalPriorityClass      = 0x00000020u;
public const uint AboveNormalPriorityClass = 0x00008000u;
public const uint HighPriorityClass        = 0x00000080u;
public const uint RealtimePriorityClass    = 0x00000100u;

// ================================================================== console

/// `COORD`: two `short`s, and the reason the console cannot address a buffer
/// wider than 32767.
public struct Coord {
    public short X;
    public short Y;
}

/// `SMALL_RECT`, whose edges are *inclusive*, unlike a `RECT`.
public struct SmallRect {
    public short Left;
    public short Top;
    public short Right;
    public short Bottom;
}

/// `CONSOLE_SCREEN_BUFFER_INFO`. `sizeof` is 22.
public struct ScreenBufferInfo {
    public Coord     Size;
    public Coord     CursorPosition;
    public ushort    Attributes;
    public SmallRect Window;
    public Coord     MaximumWindowSize;
}

/// `CONSOLE_CURSOR_INFO`.
public struct CursorInfo {
    public uint Size;
    public int  Visible;
}

/// `KEY_EVENT_RECORD`'s character, which the header makes a union of a wide
/// and an ANSI character.
public union Character {
    public ushort Unicode;
    public byte   Ansi;
}

public struct KeyEvent {
    public int       KeyDown;
    public ushort    RepeatCount;
    public ushort    VirtualKeyCode;
    public ushort    VirtualScanCode;
    public Character Char;
    public uint      ControlKeyState;
}

public struct MouseEvent {
    public Coord Position;
    public uint  ButtonState;
    public uint  ControlKeyState;
    public uint  Flags;
}

/// The `INPUT_RECORD` payload, which `EventType` says how to read. A `union`
/// and not a `variant` for exactly the reason unions exist: the tag lives
/// outside it, in the record.
public union InputEvent {
    public KeyEvent   Key;
    public MouseEvent Mouse;
    public Coord      BufferSize;
}

/// `INPUT_RECORD`. `sizeof` is 20.
public struct InputRecord {
    public ushort     EventType;
    public InputEvent Event;
}

public extern "C" {
    void* GetStdHandle(uint which);
    int   SetStdHandle(uint which, void* handle);
    int   GetConsoleMode(void* handle, uint* mode);
    int   SetConsoleMode(void* handle, uint mode);
    uint  GetConsoleOutputCP();
    int   SetConsoleOutputCP(uint codePage);
    int   SetConsoleCP(uint codePage);
    int   AllocConsole();
    int   FreeConsole();
    int   AttachConsole(uint processId);
    void* GetConsoleWindow();

    int  GetConsoleScreenBufferInfo(void* handle, ScreenBufferInfo* info);
    int  SetConsoleCursorPosition(void* handle, Coord position);
    int  SetConsoleTextAttribute(void* handle, ushort attributes);
    int  SetConsoleTitleW(ushort* title);
    uint GetConsoleTitleW(ushort* buffer, uint size);
    int  GetConsoleCursorInfo(void* handle, CursorInfo* info);
    int  SetConsoleCursorInfo(void* handle, CursorInfo* info);
    int  FillConsoleOutputCharacterW(void* handle, ushort character, uint length,
                                     Coord at, uint* written);
    int  FillConsoleOutputAttribute(void* handle, ushort attributes, uint length,
                                    Coord at, uint* written);
    int  WriteConsoleW(void* handle, ushort* text, uint units, uint* written, void* reserved);
    int  ReadConsoleW(void* handle, ushort* buffer, uint units, uint* read, void* control);
    int  SetConsoleScreenBufferSize(void* handle, Coord size);
    int  SetConsoleWindowInfo(void* handle, int absolute, SmallRect* window);

    int  ReadConsoleInputW(void* handle, InputRecord* records, uint count, uint* read);
    int  PeekConsoleInputW(void* handle, InputRecord* records, uint count, uint* read);
    int  GetNumberOfConsoleInputEvents(void* handle, uint* count);
    int  FlushConsoleInputBuffer(void* handle);
}

/// `GetStdHandle`'s argument: -10, -11 and -12 as the header defines them.
public const uint StdInput  = 0xFFFFFFF6u;
public const uint StdOutput = 0xFFFFFFF5u;
public const uint StdError  = 0xFFFFFFF4u;

public const uint EnableProcessedInput       = 0x0001u;
public const uint EnableLineInput            = 0x0002u;
public const uint EnableEchoInput            = 0x0004u;
public const uint EnableWindowInput          = 0x0008u;
public const uint EnableMouseInput           = 0x0010u;
public const uint EnableInsertMode           = 0x0020u;
public const uint EnableQuickEditMode        = 0x0040u;
public const uint EnableVirtualTerminalInput = 0x0200u;

/// `EnableVirtualTerminalProcessing` is the one that makes ANSI escape
/// sequences work, and it is off by default on a fresh console.
public const uint EnableProcessedOutput           = 0x0001u;
public const uint EnableWrapAtEol                 = 0x0002u;
public const uint EnableVirtualTerminalProcessing = 0x0004u;
public const uint DisableNewlineAutoReturn        = 0x0008u;

public const uint CodePageUtf8 = 65001u;

/// Character attributes.
///
/// The field they go in is a `WORD`, but they are declared `uint` because `|`
/// on two `ushort`s widens to `int` in this language, and a set of flags that
/// cannot be or-ed together is not usable. `SetConsoleTextAttribute` takes the
/// `ushort` the API takes, so a raw caller narrows once at the call.
public const uint ForegroundBlue    = 0x0001u;
public const uint ForegroundGreen   = 0x0002u;
public const uint ForegroundRed     = 0x0004u;
public const uint ForegroundIntense = 0x0008u;
public const uint BackgroundBlue    = 0x0010u;
public const uint BackgroundGreen   = 0x0020u;
public const uint BackgroundRed     = 0x0040u;
public const uint BackgroundIntense = 0x0080u;
public const uint ReverseVideo      = 0x4000u;
public const uint Underscore        = 0x8000u;

public const ushort KeyEventType          = 0x0001u;
public const ushort MouseEventType        = 0x0002u;
public const ushort WindowBufferSizeEvent = 0x0004u;
public const ushort MenuEventType         = 0x0008u;
public const ushort FocusEventType        = 0x0010u;

public const uint RightAltPressed  = 0x0001u;
public const uint LeftAltPressed   = 0x0002u;
public const uint RightCtrlPressed = 0x0004u;
public const uint LeftCtrlPressed  = 0x0008u;
public const uint ShiftPressed     = 0x0010u;
public const uint NumLockOn        = 0x0020u;
public const uint ScrollLockOn     = 0x0040u;
public const uint CapsLockOn       = 0x0080u;

// ===================================================================== time

/// `SYSTEMTIME`. `DayOfWeek` is 0 for Sunday and is ignored on input.
public struct SystemTime {
    public ushort Year;
    public ushort Month;
    public ushort DayOfWeek;
    public ushort Day;
    public ushort Hour;
    public ushort Minute;
    public ushort Second;
    public ushort Milliseconds;
}

/// `FILETIME`, as its two halves. It is 8 bytes but only 4-aligned, which is
/// why the header splits it and why this does too: a `ulong` field here would
/// be aligned differently and every struct containing one would be wrong.
public struct FileTime {
    public uint Low;
    public uint High;
}

public extern "C" {
    void  GetSystemTime(SystemTime* time);
    void  GetLocalTime(SystemTime* time);
    int   SetSystemTime(SystemTime* time);
    int   SetLocalTime(SystemTime* time);
    void  GetSystemTimeAsFileTime(FileTime* time);
    int   SystemTimeToFileTime(SystemTime* time, FileTime* result);
    int   FileTimeToSystemTime(FileTime* time, SystemTime* result);
    int   FileTimeToLocalFileTime(FileTime* time, FileTime* result);
    int   LocalFileTimeToFileTime(FileTime* time, FileTime* result);
    int   CompareFileTime(FileTime* left, FileTime* right);
    uint  GetTimeZoneInformation(void* information);

    ulong GetTickCount64();
    int   QueryPerformanceCounter(long* count);
    int   QueryPerformanceFrequency(long* frequency);
}

#endif
