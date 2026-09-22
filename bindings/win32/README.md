# Win32 bindings

The Windows API in two layers, both under `Win32.`, and the module name says
which one you are looking at:

| Name | What it is |
|---|---|
| `Win32.Handles` | **a header name**: the handle types, which belong to no one DLL — `windef.h` |
| `Win32.Kernel32`, `Win32.User32`, … | **a DLL name**: declarations and nothing else, spelled as Windows spells them |
| `Win32`, `Win32.Files`, `Win32.Ui`, … | **a task name**: the conveniences, written on top of those declarations |
| `Windows.DirectX`, `Windows.DirectX11` | **a subject**: the graphics layers, which are large enough to be their own thing |

The raw layer is the entry points, constants, structs, unions, enums and
delegates of fifteen libraries, plus the handle types and the names they go by,
and the COM interfaces; the convenience modules add a task-shaped layer on top
of those. Nothing is generated and nothing is marshalled: a
`WNDCLASSEXW` is a Stainless `struct` with the same fields in the same order — `sizeof` returns 80, as it does in C — and a `WNDPROC` is a
`delegate`, which is a bare function pointer Windows calls directly. A binding
is a declaration, not a wrapper.

Only the wide (`...W`) entry points are bound. The ANSI ones lose characters a
user's filesystem is entitled to contain.

## The raw layer

```
bindings/win32/api/
  Handles.sl     module Win32.Handles;    HWND, HDC, HKEY and the rest
  Kernel32.sl    module Win32.Kernel32;   errors, handles, files, memory,
                                          modules, environment, the system,
                                          processes, the console, time
  User32.sl      module Win32.User32;     windows, messages, input, clipboard
  Gdi32.sl       module Win32.Gdi32;      device contexts, pens, brushes, fonts
  AdvApi32.sl    module Win32.AdvApi32;   the registry
  Shell32.sl     module Win32.Shell32;    ShellExecuteW, known folders
  ComDlg32.sl    module Win32.ComDlg32;   the open and save dialogs
  Ole32.sl       module Win32.Ole32;      COM: apartments, activation, HRESULT
  ShellCom.sl    module Win32.ShellCom;   IShellItem, IFileDialog and friends
  ComCtl32.sl    module Win32.ComCtl32;   the common controls: tree, list,
                                          tabs, toolbar, status, progress
  Version.sl     module Win32.Version;    reading an RT_VERSION resource
  Ws2_32.sl      module Win32.Ws2_32;     Winsock: sockets, addresses, poll,
                                          getaddrinfo, and WSAStartup
  XInput.sl      module Win32.XInput;     game controllers
  XAudio2.sl     module Win32.XAudio2;    the mixer a game plays through
  Dxgi.sl        module Win32.Dxgi;       adapters, outputs, formats, the
                                          swap chain
  D3D11.sl       module Win32.D3D11;      Direct3D 11
  D3DCompiler.sl module Win32.D3DCompiler; HLSL into bytecode
```

The DirectX and audio modules were not transcribed by hand. The `*Vtbl` struct
each header generates for C is the authority on slot order and signature, and
that is what was read: a method in the wrong slot is a call to a different
function with nothing to report it, and `ID3D11DeviceContext` alone has a
hundred and eight of them.

One module per DLL, so there is never a question about where something lives or
which `-l` it wants. The console and the clock are in `Kernel32` because that is
the DLL that exports them, whatever else they look like.

Two are not DLLs. `Handles` is the handle types: `HWND` belongs to no single
library, which is why Windows keeps it in `windef.h`. `ShellCom` is the COM
interfaces the shell exposes, which likewise belong to no DLL — an interface is
a contract, and the object behind it comes from wherever activation found it.

### The one vtable that is not COM

`Win32.XAudio2`'s voices are the exception to everything above. `IXAudio2` is a
real COM object — it derives from `IUnknown`, it is counted, ARC releases it —
and `IXAudio2Voice` is not: it derives from nothing, its own first method is
slot **0**, and a voice ends when `DestroyVoice` is called rather than when a
count reaches zero. Reaching one through an ordinary `com interface` would call
`SetOutputVoices` where ARC expected `AddRef`, and the failure would be silent.

`[NoUnknown]` is what says so, and
[§8.5 of the specification](../../docs/spec/08-interop-libraries.md#nounknown-a-vtable-that-is-not-com)
is what it means. It exists for this.

### The handle types

Windows declares a handle as `DECLARE_HANDLE(HWND)` — a struct nothing ever
defines, and a pointer to it. The struct exists purely so that `HWND` and `HDC`
are different types. `Win32.Handles` says the same thing:

```csharp
public struct HWND__;
public struct HDC__;

public using HWND = HWND__*;
public using HDC  = HDC__*;
```

So a device context handed to something that wants a window is caught, rather
than being one `void*` passed to another:

```
error[SL0262]: argument 1 of 'ShowWindow' expects 'HWND__*', but 'HDC__*' was given
```

**It costs nothing.** None of those types is laid out, emitted, or present at
run time; what crosses the boundary is the same pointer it always was.

Where Windows says two names are one type, so does this — `HCURSOR` is `HICON`,
`HMODULE` is `HINSTANCE`, and `HGLOBAL` and `HLOCAL` are both `HANDLE`, exactly
as `windef.h` has it. `HGDIOBJ` is the odd one: Windows spells it `void*` so
that every pen, brush, font and bitmap converts to it and `SelectObject` can
take all of them. Here that role belongs to `byte*`, the one pointer type every
other converts to, so `HGDIOBJ` is that — same reason, same effect.

`HGDIOBJ` therefore takes any pointer, which means `SelectObject`,
`DeleteObject` and `GetObjectW` are the three entry points these types do not
help with. C accepts the same mistake for the same reason, and
[tests/cases/err-win32-handles](../../tests/cases/err-win32-handles) says so
where it lists what *is* caught.

A `void*` that is left is a `void*` in Windows too: a buffer, an address, a
reserved word, or a pointer to a struct these bindings do not declare.

### COM

`Win32.ShellCom` declares the shell's interfaces as `com interface`, which is
the language's own (§8.5 of the spec) and not a wrapper over one:

```csharp
[Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
public com interface IShellItem {
    int BindToHandler(byte* bindContext, Guid* handler, Guid* interfaceId, byte** result);
    int GetParent(byte** parent);
    int GetDisplayName(uint kind, char16** name);
    int GetAttributes(uint mask, uint* attributes);
    int Compare(byte* other, uint hint, int* order);
}
```

**The method order is the vtable.** Nothing in one of these declarations may be
reordered or left out, because slot 7 has to be slot 7 — which is why several
methods take a `byte*` for an interface these bindings do not declare. The
parameter is never passed; the slot has to exist.

**ARC calls AddRef and Release**, so nothing in the conveniences counts a
reference and nothing there can leak one. The one thing to know is that ARC
releases at the end of a scope and `CoUninitialize` is a call in the middle of
one — so an object must go out of scope before the apartment does. `Win32.Com`'s
`Uninitialize` says so at greater length.

An out-parameter is `byte**` rather than the interface, because that is what
`void**` is, and the caller adopts what comes back with a cast:

```csharp
byte* raw = null;
SHCreateItemFromParsingName(path, null, iidof(IShellItem), &raw);
IShellItem item = (IShellItem)raw;      // +1 from the shell, released by ARC
```

`iidof(T)` is the `[Guid]` on the declaration, folded to a constant — C's
`IID_IShellItem` without the header that had to declare it.

**Importing the whole raw layer is free and needs no `-l` at all.** A
declaration nothing calls is not a reference, so the linker never looks for it:

```
stainless build app.sl bindings/win32/api
```

`tests/cases/win32-raw` is that, as a test — it imports seven of these modules
and links with no libraries named. Not all of them: `Ws2_32` and `Version` name
their own library with a `#pragma`, because neither ws2_32 nor version is
pulled in by the C runtime the way kernel32 and its neighbours are.

The only function bodies in the raw layer are the handful of constants that are
pointer-shaped and so cannot be written as `const`: `InvalidHandle()`,
`LocalMachine()`, `CursorArrow()` and their neighbours. Everything else is a
declaration, a type or a constant.

## The conveniences

```
bindings/win32/
  Win32.sl         module Win32;              BOOL, handles, error text, buffers
  Files.sl         module Win32.Files;        paths, attributes, directory walks
  Environment.sl   module Win32.Environment;  variables, command line, directories
  Machine.sl       module Win32.Machine;      system info, memory, pages, DLLs
  Terminal.sl      module Win32.Terminal;     console modes, colours, raw keys
  Clock.sl         module Win32.Clock;        SYSTEMTIME, FILETIME, Stopwatch
  Tasks.sl         module Win32.Tasks;        child processes and pipes
  Ui.sl            module Win32.Ui;           message loop, windows, clipboard
  Drawing.sl       module Win32.Drawing;      COLORREF, fonts, double buffering
  Registry.sl      module Win32.Registry;     keys and values, as a Result
  Com.sl           module Win32.Com;          apartments, activation, HRESULT
  Shell.sl         module Win32.Shell;        opening things, known folders,
                                              shell items
  Dialogs.sl       module Win32.Dialogs;      the file dialogs, both generations
  Resources.sl     module Win32.Resources;    what the binary carries inside it
  Gamepad.sl       module Win32.Gamepad;      pads, dead zones, edges, rumble
  Sound.sl         module Win32.Sound;        a mixer: several sounds at once
  DirectX.sl       module Windows.DirectX;    adapters and the shader compiler
  DirectX11.sl     module Windows.DirectX11;  a device, a swap chain, a frame
```

The last two are named `Windows.` rather than `Win32.` because they are a
subject rather than a task: Direct3D is large enough that a program using it is
mostly using it, and the name should say which API it is looking at. `Gamepad`
and `Sound` keep the `Win32.` prefix, being one convenience layer each over one
DLL.

These exist only where saying it in Stainless is genuinely better than saying it
in C: **text**, which crosses as UTF-8 and has to be widened; **lifetime**,
which a destructor can hold; and **failure**, which a `Result` can make
unignorable. Nothing here hides the API — everything Windows declares is
`public` in the raw layer and reachable by its real name.

Which library each wants:

| Module | `-l` |
|---|---|
| `Win32`, `Win32.Files`, `Win32.Environment`, `Win32.Machine`, `Win32.Terminal`, `Win32.Clock`, `Win32.Tasks` | — |
| `Win32.Ui` | `user32` |
| `Win32.Drawing` | `gdi32` (and `user32`) |
| `Win32.Registry` | `advapi32` |
| `Win32.Com` | `ole32` |
| `Win32.Shell` | `shell32` (and `user32`, `ole32`) |
| `Win32.Dialogs` | `comdlg32` (and `user32`, `ole32`) |
| `Win32.Resources` | `user32` |
| `Win32.Gamepad` | `xinput` |
| `Win32.Sound` | `xaudio2` (and `ole32`) |
| `Windows.DirectX` | `dxgi`, `d3dcompiler` |
| `Windows.DirectX11` | `d3d11` (and the two above) |

The first row needs none: kernel32 is pulled in by the C runtime every Windows
program already links.

## Using them

Name the modules you use:

```
stainless build gui.sl bindings/win32/api/Handles.sl bindings/win32/api/Kernel32.sl \
    bindings/win32/api/User32.sl bindings/win32/Win32.sl bindings/win32/Ui.sl
```

or take the whole directory:

```
stainless build app.sl bindings/win32
```

Neither needs a `-l`, because each convenience module names its own library with
`#pragma comment(lib, "...")`. Compiling a wrapper is still what makes that
library necessary — an undefined symbol is an error before the dead-strip that
would have removed it — so the second form links every library the directory names — Direct3D,
XAudio2 and XInput included — whether or not the program calls into them. Naming only what you use is how to avoid that.

That is also why none of this is in `stdlib/`, which is compiled into every
program: a `CreateWindowExW` in there would make every Stainless program on
every platform need `user32.lib`.

Every file is wrapped in `#if WINDOWS`, so on Linux or macOS these modules exist
and are empty rather than failing to build. A cross-platform program can import
them unconditionally and guard its own uses.

## What the conveniences are for

**Text in both directions.** A `String` is UTF-8 and a `...W` function wants
UTF-16, so a call is `path.ToUtf16().ToPointer()` going out. Coming back is the
harder half — a wide API writes into a buffer the caller owns — so
`Win32.WideBuffer` owns one and frees it in its destructor:

```csharp
var buffer = new WideBuffer(32768u);
uint units = GetModuleFileNameW(null, buffer.Pointer(), buffer.Capacity);
String path = buffer.Text(units);
```

`Machine.ExecutablePath()` is that, once, with a name.

**The failure conventions**, which are three and are not interchangeable.
`CreateFileW` returns `INVALID_HANDLE_VALUE`; `CreateWindowExW` returns null;
`RegOpenKeyExW` returns the error code itself and never touches
`GetLastError`. `Win32.IsInvalid` covers the first two, `Win32.Succeeded` reads
a `BOOL`, and `Win32.Registry` returns a `Result` so that a value that was never
read cannot be used.

**`Win32.LastErrorMessage()`**, which is `FormatMessageW` into a buffer with the
trailing CR LF trimmed — the thing every program writes once.

## The window procedure

A `delegate` captures nothing, so a `WNDPROC` is an ordinary module-level
function and per-window state goes where Win32 has always kept it:

```csharp
nint Procedure(HWND window, uint message, nuint wParam, nint lParam) {
    State* state = (State*)(nuint)GetWindowLongPtrW(window, GwlpUserData);
    switch (message) {
        case WmDestroy: PostQuitMessage(0); return 0;
        default:        break;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}
```

It is in neither layer, because there is nothing to wrap.
[samples/win32/window.sl](../../samples/win32/window.sl) is a working window
built this way, with a class, a message loop, double-buffered GDI painting and
keyboard handling. [samples/win32/report.sl](../../samples/win32/report.sl) is
the same for the parts with no window.

## Things to know

- **`uint` arithmetic widens to `long`.** `a | b` on two `uint`s is a `uint`,
  but `a - b` is a `long` and needs a cast back. The console's colour constants
  are `uint` rather than the `ushort` the field takes for this reason:
  `ushort | ushort` is an `int`, and a flag set that cannot be or-ed together is
  not usable. `Terminal.SetColour` narrows once.
- **There is no `->`.** `(*state).Clicks`, not `state->Clicks`.
- **GDI ownership is not enforced and cannot be.** Every object `Create...`
  returns must be selected out of its device context before `DeleteObject`, and
  a stock object from `GetStockObject` must never be deleted at all.
  `Drawing.OffScreen` is the one place that pairing is done for you.
- **`CreateProcessW` may write to the command line it is given**, so it cannot
  be a literal. `Tasks.Run` copies with `Win32.Copy` first; a caller using the
  declaration directly has to do the same.
- **An inline array cannot be passed by value.** `WIN32_FIND_DATAW` is a
  `struct` with the two `WCHAR` arrays the header gives it, so it is a plain
  local — but C decays an array parameter to a pointer, and copying 592 bytes
  would be neither that nor cheap, so `Win32.Files` takes it `ref`.
- **`Win32.Terminal`, not `Win32.Console`.** A module is reached by its last name
  segment, so a `Win32.Console` would shadow `Standard.Console` in every file
  that imported it.

## Resources

A Windows binary carries data inside itself, indexed by **type** and **name**.
Putting something there is a build step rather than a call — a `.rc` listed
among the sources, compiled by `llvm-rc` and folded in by the linker (see
[§2.2 of the packages doc](../../docs/packages.md)) — and `Win32.Resources` is
the reading half.

**`Standard.Resources` is the portable half, and is usually the one to reach
for.** It reads bytes, string tables and bitmaps identically on every target,
and it needs no `-l` at all. What is *here* is the part that is Windows by
nature: an icon or cursor as an `HICON`, a menu as an `HMENU`, an accelerator
table, enumeration of what a binary holds, and reading the resources of a
*different* binary. Reach for this when the answer you want is a Windows handle
rather than bytes.

What makes this different from every other part of the API is that **Windows
reads the resource directory on the program's behalf**. `LoadIconW`,
`LoadStringW`, `LoadMenuW`, `CreateDialogParamW` and `LoadAcceleratorsW` each
walk in there and hand back a finished object; `ImageList_LoadImageW` slices a
toolbar's strip out of it. So the raw declarations sit where Windows puts them
— the find/load/lock trio in `Win32.Kernel32`, the loaders in `Win32.User32`,
the image list in `Win32.ComCtl32` — and `Win32.Resources` is the layer that
makes naming one bearable:

```csharp
import Win32.Resources;
import Win32.User32;

String ready = Resources.Text(201u);                        // RT_STRING
byte[] data  = Resources.Bytes(Resources.Id(301), RtRcData());
HICON  icon  = Resources.Icon(Resources.Id(1));             // RT_GROUP_ICON
HMENU  menu  = Resources.Menu(Resources.Id(1));             // RT_MENU

foreach (var name in Resources.Names(RtBitmap())) { ... }   // what is in there
```

**A name is a string or an integer, through the same parameter.** Windows
reserves the bottom 64K of the pointer range for the second and calls the cast
`MAKEINTRESOURCE`; `Resources.Id` is that cast, and `IsId`, `IdOf` and `NameOf`
are the other direction, for a callback that has to ask which it was given.
The `RT_` types are functions rather than constants for the same reason the
standard cursors are — they are integers pretending to be strings, and
Stainless has no `const char16*`.

**Nothing here is freed.** A resource lives in the mapped image, so
`LoadResource` hands back a pointer into memory that is already there and
`LockResource` is a cast. `FreeResource` has done nothing since Win32 and is
deliberately not declared. `Resources.Pointer` gives that pointer straight out
— read-only, valid as long as the module is — and `Resources.Bytes` copies for
anything that outlives the call.

**`RT_VERSION` is the odd one out** and lives in `Win32.Version`, over
`version.dll`. It is not a value but a small tree -- a fixed block of numbers
plus per-language string tables -- so it is read with `VerQueryValueW` rather
than by locking bytes, and it is read from a *file* rather than from a loaded
module. `Resources.Version()` finds this program's own path and unpacks the
four-part number; `Resources.VersionOf(path)` asks about anything else.

**Reading another binary's resources** goes through
`Resources.OpenForResources`, which is `LoadLibraryExW` with
`LOAD_LIBRARY_AS_DATAFILE`: the file is mapped without `DllMain` running and
without its imports being resolved, which is the only safe way to pull an icon
out of an executable this program did not build.

## What is not bound

- **COM beyond the shell.** `Win32.Ole32` and `Win32.ShellCom` bind the
  activation half and the shell's interfaces — `IShellItem`,
  `IShellItemArray`, `IFileDialog` and both its directions — and `Win32.Com`,
  `Win32.Shell` and `Win32.Dialogs` are the conveniences over them; DXGI,
  Direct3D 11 and XAudio2 are COM too, and are bound. What is not here is
  everything else COM reaches: Direct2D, WIC, the Windows Property
  System, `ITaskbarList3`, `IDispatch` and automation.
- **A Stainless object handed *out* as a COM object.** `com class` exists and
  works (§8.5), so this is a matter of writing the class; what is absent is a
  class factory and `DllGetClassObject`, which is what would let another
  process ask for one.
- **GDI+**, Direct3D 12, WMI, the event log.
- **32-bit Windows.** The types and structures are the right width on both,
  but the declarations name no calling convention, and every Win32 function
  on x86 is `__stdcall` — so a 32-bit program links against none of them.
