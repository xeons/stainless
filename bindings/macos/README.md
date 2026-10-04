# macOS bindings

Two kinds of thing live here: Apple's frameworks, generated from the SDK's
headers, and a hand-written terminal and event layer over libSystem.

```
bindings/macos/
  CoreFoundation/ ... vmnet/   module MacOS.<Framework>;   generated, a file per header
  System/                      module MacOS.System;        what those use from usr/include
  skipped.txt                  every declaration not bound, and why
  api/Termios.sl               module MacOS.Termios;       hand-written, below
  api/Events.sl                module MacOS.Events;
  Terminal.sl                  module MacOS.Terminal;
```

A binding is a declaration, not a wrapper, and every file is `#if MACOS`, so
the bindings compile on every host and mean something on a Mac.

## The frameworks

Every directory but `api/` is written by
[tools/Stainless.Bindgen](../../tools/Stainless.Bindgen) from the SDK and MUST
NOT be edited; [tools/bindgen.sh](../../tools/bindgen.sh) regenerates them on a
Mac. They are the 41 frameworks whose API is C:

> Accelerate, ApplicationServices, AudioToolbox, AudioUnit, Carbon, CFNetwork,
> ColorSync, CoreAudio, CoreAudioTypes, CoreFoundation, CoreGraphics, CoreMedia,
> CoreMIDI, CoreServices, CoreText, CoreVideo, DirectoryService, DiskArbitration,
> DVDPlayback, ForceFeedback, GLUT, GSS, Hypervisor, ICADevices, ImageIO, IOKit,
> IOSurface, LatentSemanticMapping, LDAP, MediaToolbox, NetFS, OpenAL, OpenCL,
> OpenGL, PCSC, Security, SystemConfiguration, TWAIN, VideoDecodeAcceleration,
> VideoToolbox, vmnet

A program names a framework's directory, and those of the modules it
imports, as sources, and imports the module:

```
stainless build app.sl bindings/macos/CoreFoundation bindings/macos/System
```

```csharp
import MacOS.CoreFoundation;

var text = CFStringCreateWithCString(null, "hello", (uint)CFStringBuiltInEncodings.UTF8);
Console.WriteLine($"{CFStringGetLength(text)}");
CFRelease(text);
```

Each module names its framework with `#pragma comment(framework, ...)`, so a
program using it links it; one that is only headers, as CoreAudioTypes is,
names nothing. Naming every module costs little: a CoreFoundation program
built against all 123,000 lines takes under a second on an M4, and code is
emitted only for what the program reaches.

### What C becomes

| C | Stainless |
|---|---|
| function | `public extern "C"`; a variadic one stays variadic |
| `static inline` function | not bound: nothing exports it |
| struct, union, bit-field | the same, with `[Packed]`, `[Align(N)]` and `[Pack(N)]` |
| `#pragma pack(N)` | `[Pack(N)]` |
| struct declared with no body | `public struct X;`, used behind a pointer |
| `typedef` of a type | `public using`; of a function pointer, a `delegate`; of a block, an `objc closure` |
| `typedef void X` | `void`, wherever `X` is written |
| `typedef T X[N]` | `T[N]`; a parameter of it is `T*`, as C passes it |
| `NS_ENUM`, `CF_ENUM` | `enum : T` |
| `NS_OPTIONS`, `CF_OPTIONS` | `[Flags] enum : T` |
| an enum with no name | `public const` under the C names |
| `#define` of an integer or float | `public const`, the value clang folded |
| `extern` variable | `public extern "C"`; an array of unknown length as its first element, whose address is the array's |
| array in a struct | `T[N]`; a multi-dimensional one flattened, which is the same bytes |
| flexible array member | left out, as C's `sizeof` leaves it out |
| `uint32_t`, `size_t`, ... | `uint`, `nuint`, ... |

Where arm64 and x86-64 disagree about a declaration, both are written, under
`#if ARM64` and `#else`.

### Names

A C name is the Stainless name, so Apple's documentation finds it. One that
is a Stainless keyword is escaped, `@in`, and links as itself.

An enum's members lose the prefix they share, at a word boundary:
`kCFCompareLessThan` is `CFComparisonResult.LessThan`. A type C leaves unnamed
is named after where it is: the block `CFRunLoopPerformBlock` takes is
`CFRunLoopPerformBlockBlock`, and an unnamed struct a field holds is the
record's name and the field's.

### MacOS.System

What a framework uses from outside every framework -- `pid_t`, `OSStatus`,
`UInt32`, `mach_port_t` -- is in `MacOS.System`, and only that. Its files are
named after their headers' paths, `sys__types__pid_t.sl` for
`sys/_types/_pid_t.h`.

### What is not bound

[skipped.txt](skipped.txt) lists every declaration the generator could not
write, with the reason, so a regeneration shows what started or stopped
binding. Most are:

- **`static inline` functions**, whose bodies are in the header and which no
  library exports.
- **Objective-C types** in a C framework's headers -- a dispatch queue, an
  `NSString` constant. The Objective-C frameworks are the next phase.
- **A `va_list`**, which Stainless has no way to make, and **`long double`**.
- **A string or object `#define`**, which a `const` cannot hold.
- **Anything that uses something above**, named in the reason.

Left out whole:

- **The 70 Swift-only frameworks** -- SwiftUI, SwiftData, Charts, CryptoKit,
  FoundationModels, WeatherKit, the `_X_SwiftUI` overlays and the rest -- have
  no C or Objective-C headers to read.
- **Kerberos**, whose `gssapi.h` is the GSS framework's, superseded by it.
- **Tcl and Tk**, deprecated, and whose `tcl.h` is in `usr/include` as well.
- **OpenGL's `gl3.h`, `gl3ext.h` and `CGLMacro.h`**, which cannot share a
  translation unit with `gl.h`; the classic API is bound.

### What is verified

[tests/cases/macos-bindings-layout](../../tests/cases/macos-bindings-layout),
also generated, holds every bound struct's size, alignment and field offsets
and every bound enumerator's and integer macro's value -- 38,421 checks --
against what clang says, built for the target the suite runs as. The macOS
lane runs it on Apple silicon and the Rosetta lane as Intel code.

### Regenerating

```
tools/bindgen.sh          # on a Mac; about three minutes on an M4
```

The generator compiles each framework's headers, its subframeworks' included,
as Objective-C for `arm64-apple-macosx13.0` and `x86_64-apple-macosx13.0`
with `-ast-dump=json`, and keeps the declarations whose header is in the
framework. A `#define` is asked of clang in the same translation unit, as
`enum { v = (NAME) }` for its value and `__typeof__((NAME))` for its type; a
struct under `#pragma pack`, whose value the dump omits, is asked its
`_Alignof`.

## The terminal

`MacOS.Terminal` has the functions `Linux.Terminal` has, with the same names
and the same behaviour, so a program choosing between them needs an `#if` on
the import and nothing else. The layer under it is where they differ:

| | Linux | macOS |
|---|---|---|
| `tcflag_t`, `speed_t` | 4 bytes | 8 bytes |
| `NCCS` | 32 | 20 |
| `sizeof(struct termios)` | 60 | 72 |
| `ICANON` | 0x2 | 0x100 |
| `ECHO` | 0x8 | 0x8 |
| `ISIG` | 0x1 | 0x80 |
| `VMIN`, `VTIME` | 6, 5 | 16, 17 |
| `TIOCGWINSZ` | 0x5413 | 0x40087468 |

A `termios` copied from the other platform is wrong in every field after the
first, and `tcsetattr` takes it without complaint.

**`ioctl` is declared variadic, and MUST stay so.** On Apple silicon a variadic
argument travels on the stack rather than in a register; declared with a fixed
third parameter, the `winsize` pointer is read from wherever the stack points.
`open` in `Events.sl` is variadic for the same reason.

## The event loop

kqueue is one wait for what Linux spreads over four kinds of descriptor:

| Linux | macOS |
|---|---|
| `epoll` | `kqueue` and `kevent` |
| `eventfd` | `EVFILT_USER`, fired with `NOTE_TRIGGER` |
| `timerfd` | `EVFILT_TIMER`, the period in `data` |
| `inotify` | `EVFILT_VNODE`, on a file opened `O_EVTONLY` |

One `kevent` call both changes what is watched and waits. A user event or a
vnode event SHOULD be added with `EV_CLEAR`, or it reports again on every wait
after the first.

[tests/cases/macos-terminal](../../tests/cases/macos-terminal) compiles a C
file that returns what Darwin's headers say and compares every constant, every
`sizeof` and the offsets that matter against these, then runs a kqueue with a
user event, a timer and a watched file. It runs on macOS only.
