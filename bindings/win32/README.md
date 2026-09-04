# Win32 bindings

The Windows API, declared in Stainless. Nine modules, about 300 entry points,
460 constants and 36 structs, unions, enums and delegates.

There is no marshalling layer here and there is nothing generated. Stainless
already speaks the platform C ABI, so a `WNDCLASSEXW` is a Stainless `struct`
with the same fields in the same order — `sizeof` returns 80, as it does in C —
and a `WNDPROC` is a `delegate`, which is a bare function pointer Windows calls
directly. A binding is a declaration, not a wrapper.

What the modules add on top of the declarations is the handful of places where
saying it in Stainless is genuinely better than saying it in C: **text**, which
crosses as UTF-8 and has to be widened; **lifetime**, which a destructor can
hold; and **failure**, which a `Result` can make unignorable.

Only the wide (`...W`) entry points are bound. The ANSI ones lose characters a
user's filesystem is entitled to contain.

## Using them

The bindings are **not** part of the standard library. They are source you
compile with your program:

```
stainless build app.sl bindings/win32/Core.sl bindings/win32/User.sl -l user32
```

Name the modules you use rather than the whole directory. Compiling a binding is
what makes its library necessary — an undefined symbol is an error before the
dead-strip that would have removed it — so `bindings/win32` as a whole wants
every `-l` in the table below, whether or not the program calls into them.

That is also why these are not in `stdlib/`, which is compiled into every
program: a `CreateWindowExW` in there would make every Stainless program on
every platform need `user32.lib`.

| Module | Library | What is in it |
|---|---|---|
| `Win32` | — | handles, `BOOL`, error text, `WideBuffer`, `ByteBuffer` |
| `Win32.Kernel` | — | files, directories, memory, DLLs, environment, processes |
| `Win32.Terminal` | — | console modes, colours, the cursor, raw key input |
| `Win32.Time` | — | `SYSTEMTIME`, `FILETIME`, the performance counter, `Stopwatch` |
| `Win32.Process` | — | `CreateProcessW`, pipes, running a command and reading it |
| `Win32.User` | `user32` | windows, messages, painting, input, the clipboard |
| `Win32.Gdi` | `gdi32` | device contexts, pens, brushes, fonts, `BitBlt` |
| `Win32.Registry` | `advapi32` | keys and values, with `Result` |
| `Win32.Shell` | `shell32`, `comdlg32` | `ShellExecuteW`, known folders, file dialogs |

The first five need no `-l`: kernel32 is pulled in by the C runtime every
Windows program already links.

Every file is wrapped in `#if WINDOWS`, so on Linux or macOS these modules exist
and are empty rather than failing to build. A cross-platform program can import
them unconditionally and guard its own uses.

## What the wrappers are for

Everything Windows declares is `public extern "C"` and reachable by its real
name, so nothing here hides the API. The extra functions exist where the raw
call is awkward from Stainless:

**Text in both directions.** A `String` is UTF-8 and a `...W` function wants
UTF-16, so a call is `path.ToUtf16().ToPointer()` going out. Coming back is the
harder half — a wide API writes into a buffer the caller owns — so `WideBuffer`
owns one and frees it in its destructor:

```csharp
var buffer = new WideBuffer(32768u);
uint units = GetModuleFileNameW(null, buffer.Pointer(), buffer.Capacity());
String path = buffer.Text(units);
```

`Kernel.ExecutablePath()` is that, once, with a name.

**The failure conventions**, which are three and are not interchangeable.
`CreateFileW` returns `INVALID_HANDLE_VALUE`; `CreateWindowExW` returns null;
`RegOpenKeyExW` returns the error code itself and never touches
`GetLastError`. `Win32.IsInvalid` covers the first two, `Win32.Succeeded` reads
a `BOOL`, and the registry's wrappers return a `Result` so that a value that was
never read cannot be used.

**`Win32.LastErrorMessage()`**, which is `FormatMessageW` into a buffer with the
trailing CR LF trimmed — the thing every program writes once.

## The window procedure

A `delegate` captures nothing, so a `WNDPROC` is an ordinary module-level
function and per-window state goes where Win32 has always kept it:

```csharp
long Procedure(void* window, uint message, ulong wParam, long lParam) {
    State* state = (State*)(nuint)GetWindowLongPtrW(window, GwlpUserData);
    if (message == WmDestroy) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(window, message, wParam, lParam);
}
```

`samples/win32/window.sl` is a working window built this way, with a class, a
message loop, double-buffered GDI painting and keyboard handling.

## Things to know

- **`uint` arithmetic widens to `long`.** `a | b` on two `uint`s is a `uint`,
  but `a - b` is a `long` and needs a cast back. The console's colour constants
  are `uint` rather than `ushort` for this reason: `ushort | ushort` is an `int`,
  and every use would otherwise need a cast.
- **There is no `->`.** `(*state).Clicks`, not `state->Clicks`.
- **GDI ownership is not enforced and cannot be.** Every object `Create...`
  returns must be selected out of its device context before `DeleteObject`, and
  a stock object from `GetStockObject` must never be deleted at all.
- **`CreateProcessW` may write to the command line it is given**, so it cannot
  be a literal. `Process.Run` copies into a `WideBuffer` first; a caller using
  the raw entry point has to do the same.

## What is not bound

- **Anything needing an inline fixed-size array field**, which Stainless does
  not have. `WIN32_FIND_DATAW` ends in two `WCHAR` arrays, so `Kernel.FindData`
  owns the 592 bytes as a block and reads the fields at the offsets the header
  gives — a class with accessors rather than a struct with fields. `LOGFONTW` is
  the same shape and is not bound; `CreateFontW` takes the face name as a
  pointer and is.
- **COM**, and so everything reached through it: the shell's newer interfaces,
  Direct2D, WIC, `SHGetKnownFolderPath`. That needs vtable layout and `IUnknown`,
  which is a project rather than a binding.
- **Winsock**, GDI+, DirectX, the Common Controls, WMI, the event log.
- **32-bit Windows.** `LRESULT` and `LPARAM` are written `long` and `WPARAM`
  `ulong` because Windows is 64-bit; a 32-bit target would want `nint`/`nuint`.
