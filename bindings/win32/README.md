# Win32 bindings

The Windows API in two layers, both under `Win32.`, and the module name says
which one you are looking at:

| Name | What it is |
|---|---|
| `Win32.Handles` | **a header name**: the handle types, which belong to no one DLL — `windef.h` |
| `Win32.Kernel32`, `Win32.User32`, … | **a DLL name**: declarations and nothing else, spelled as Windows spells them |
| `Win32`, `Win32.Files`, `Win32.Ui`, … | **a task name**: the conveniences, written on top of those declarations |

The raw layer is 273 entry points, 511 constants and 28 structs, unions, enums
and delegates across seven libraries, plus the 12 handle types and the 17 names
they go by, and 7 COM interfaces; the thirteen convenience modules add 215
functions and 9 types on top. Nothing is generated and nothing is marshalled: a
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
```

One module per DLL, so there is never a question about where something lives or
which `-l` it wants. The console and the clock are in `Kernel32` because that is
the DLL that exports them, whatever else they look like.

Two are not DLLs. `Handles` is the handle types: `HWND` belongs to no single
library, which is why Windows keeps it in `windef.h`. `ShellCom` is the COM
interfaces the shell exposes, which likewise belong to no DLL — an interface is
a contract, and the object behind it comes from wherever activation found it.

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

`tests/cases/win32-raw` is that, as a test — it imports all six modules and
links with no libraries named.

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
```

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

The first row needs none: kernel32 is pulled in by the C runtime every Windows
program already links.

## Using them

Name the modules you use:

```
stainless build gui.sl bindings/win32/api/Kernel32.sl bindings/win32/api/User32.sl \
    bindings/win32/Win32.sl bindings/win32/Ui.sl
```

or take the whole directory:

```
stainless build app.sl bindings/win32
```

Neither needs a `-l`, because each convenience module names its own library with
`#pragma comment(lib, "...")`. Compiling a wrapper is still what makes that
library necessary — an undefined symbol is an error before the dead-strip that
would have removed it — so the second form links all five whether or not the
program calls into them. Naming only what you use is how to avoid that.

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
uint units = GetModuleFileNameW(null, buffer.Pointer(), buffer.Capacity());
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
long Procedure(HWND window, uint message, ulong wParam, long lParam) {
    State* state = (State*)(nuint)GetWindowLongPtrW(window, GwlpUserData);
    if (message == WmDestroy) { PostQuitMessage(0); return 0; }
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

## What is not bound

- **COM beyond the shell.** `Win32.Ole32` and `Win32.ShellCom` bind the
  activation half and the shell's interfaces — `IShellItem`,
  `IShellItemArray`, `IFileDialog` and both its directions — and `Win32.Com`,
  `Win32.Shell` and `Win32.Dialogs` are the conveniences over them. What is not
  here is everything else COM reaches: Direct2D, WIC, the Windows Property
  System, `ITaskbarList3`, `IDispatch` and automation.
- **A Stainless object handed *out* as a COM object.** `com class` exists and
  works (§8.5), so this is a matter of writing the class; what is absent is a
  class factory and `DllGetClassObject`, which is what would let another
  process ask for one.
- **Winsock**, GDI+, DirectX, the Common Controls, WMI, the event log.
- **32-bit Windows.** `LRESULT` and `LPARAM` are written `long` and `WPARAM`
  `ulong` because Windows is 64-bit; a 32-bit target would want `nint`/`nuint`.
