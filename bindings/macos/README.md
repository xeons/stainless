# macOS bindings

Two kinds of thing live here: Apple's frameworks, generated from the SDK's
headers, and a hand-written terminal and event layer over libSystem.

```
bindings/macos/
  CoreFoundation/ ... vmnet/   module MacOS.<Framework>;   generated, a file per header
  System/                      module MacOS.System;        what those use from usr/include
  skipped.txt                  every declaration not bound, and why
  unanswered.txt               what the headers declare and the runtime does not answer
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
Mac. Every framework in the SDK with a C or Objective-C header is generated --
196 of them, 438,000 lines -- except these:

| Left out | Why |
|---|---|
| Kernel, DriverKit | kernel and driver extensions, which no program links |
| Kerberos | its `gssapi.h` is GSS's, which supersedes it |
| Tcl, Tk, Ruby | interpreters' own C APIs, deprecated, and in `usr/include` too |
| vecLib | the same headers as Accelerate's vecLib subframework |
| Cocoa | an umbrella over Foundation, AppKit and CoreData |
| AccessorySetupKit | its headers import UIKit, which macOS has not got |
| the `_X_SwiftUI` overlays and the 70 Swift-only frameworks | no C or Objective-C header to read |

A program names the directories as sources -- all of them is simplest -- and
imports the modules it uses:

```
stainless build app.sl $(ls -d bindings/macos/*/ | grep -v api/)
```

```csharp
import MacOS.CoreFoundation;
import MacOS.Foundation;

var text = CFStringCreateWithCString(null, "hello", (uint)CFStringBuiltInEncodings.UTF8)!;
Console.WriteLine($"{CFStringGetLength(text)}");      // 5; ARC releases it
var same = (NSString)text;                            // toll-free bridged
```

Each module names its framework with `#pragma comment(framework, ...)`, and
a framework is linked when the program reaches something its module declares:
a function it calls, a variable it reads, a class it names or derives from, a
message a member of the module declares (so a category's methods link the
category's framework). A program naming every directory links only what it
uses, and one built against the newest SDK runs on an older macOS that lacks
frameworks it never touched. A framework that is only headers, as
CoreAudioTypes is, names nothing.

Naming every module costs little, and code is emitted only for what the
program reaches. Measured on an M4, a whole build of a small program:

| A program importing | Modules it compiles | Lines | Build |
|---|---|---|---|
| Foundation, or AppKit | 39 | 199,000 | 1.1 s |
| every module | 197 | 438,000 | 2.2 s |

Foundation's closure is AppKit's because `NSUserNotification` names AppKit's
`NSImage`; whole-program binding makes the cycle cost nothing but parsing.

### What C becomes

| C | Stainless |
|---|---|
| function | `public extern "C"`; a variadic one stays variadic |
| `static inline` function | not bound: nothing exports it |
| struct, union, bit-field | the same, with `[Packed]`, `[Align(N)]` and `[Pack(N)]` |
| `__attribute__((packed))` on a field | `[Packed]` on the field |
| `#pragma pack(N)` | `[Pack(N)]` |
| struct declared with no body | `public struct X;`, used behind a pointer |
| `typedef` of a type | `public using`; of a function pointer, a `delegate`; of a block, an `objc closure` |
| `typedef void X` | `void`, wherever `X` is written |
| `typedef T X[N]` | `T[N]`; a parameter of it is `T*`, as C passes it |
| `NS_ENUM`, `CF_ENUM` | `enum : T` |
| `NS_OPTIONS`, `CF_OPTIONS` | `[Flags] enum : T` |
| an enum with no name | `public const` under the C names |
| `#define` of an integer or float | `public const`, the value clang folded |
| `#define` of a string literal | `public const byte*` |
| `#define` of `CFSTR("...")` or `@"..."` | `public const CFStringRef` or `public const NSString`, the constant object clang makes |
| `ext_vector_type`, `vector_size` | `vfloat4` and the rest; `simd_float4` is a `public using` of it, and `simd_float4x4` a struct of them |
| `va_list` | `VaList` |
| `long double` | `ndouble` |
| `__int128` | `int128` |
| `extern` variable | `public extern "C"`; an array of unknown length as its first element, whose address is the array's |
| array in a struct | `T[N]`; a multi-dimensional one flattened, which is the same bytes |
| flexible array member | left out, as C's `sizeof` leaves it out |
| `uint32_t`, `size_t`, ... | `uint`, `nuint`, ... |
| a Core Foundation type | an object ARC counts; see below |
| an object in a struct, behind a pointer, or given to a callback | the pointer, which owns nothing |

### What Objective-C becomes

| Objective-C | Stainless |
|---|---|
| `@interface` | `extern objc class`; `[ObjCRoot]` on one with no superclass |
| `@protocol` | `objc interface`; one named like a class gains `Protocol` and keeps its name in `[ObjCName]` |
| `@optional` | `[Optional]` |
| category | the class declared again, in the category's module, with its members and protocols |
| method | a `[Selector]` method named by its whole selector: `initWithFrame:display:` is `InitWithFrameDisplay` |
| `+` method, `class` property | `static`; on a protocol, `static abstract` |
| `...` | `...`: a variadic message is sent as C sends one |
| property | a `[Selector(getter, setter)]` property; `readonly` has the getter alone |
| `instancetype` | `Self` |
| `id`, `id<P>`, `Class`, `SEL` | `AnyObject`, `P`, `Class`, `Selector` |
| `NSArray<T *> *`, `ObjectType` | `NSArray`, `AnyObject`: generics are erased |
| `_Nonnull` | `T` |
| `_Nullable`, or nothing said | `T?` |
| `NSError **` | `out NSError?` |
| block | `objc closure`, named after where it is: `NSArrayEnumerateObjectsUsingBlockBlock` |
| `BOOL` in a message or a block | `bool` |
| `ns_returns_retained` against the method family | `[ReturnsRetained]`, `[ReturnsNotRetained]` |
| `extern NSString *const` | `public extern "C"`, read and never written |
| `typedef NSString *X` (`NS_TYPED_ENUM`) | `public using X = NSString;` |

What `alloc` returns is never nil, and is written so whatever the header
says; any other result the header says nothing about is optional. A result
declared `T` that arrives nil stops the program, naming the message, so
trusting a header is never undefined.

A member name another member of the class already has -- a class method and
an instance method of one selector, or a property and a method -- is changed
by a fixed rule: the class method gains `Class` before it, the property
`Property` after it, the method `Method`. A message a property already
answers is not declared again.

### Core Foundation

Every Core Foundation object is an Objective-C object on Apple's systems, so
each CF type is a `[CFType]` class ARC counts, and nothing calls `CFRelease`:

```csharp
[CFType]                       public extern objc class CFTypeRef { }
[CFType("CFStringGetTypeID")]  public extern objc class CFStringRef : CFTypeRef { }
[CFType]                       public extern objc class CFMutableStringRef : CFStringRef { }
```

A typedef is a CF type when it points at a struct bridged to an Objective-C
class, or at one with a `GetTypeID` function of its name. The mutable typedef
of a struct derives from the immutable one and shares its `CFTypeID`.

What a function returns follows the Create rule, as clang reads it: a name
holding `Create` or `Copy` as a word hands it over, `[ReturnsRetained]`, and
anything else hands it back at +0. `cf_returns_retained` and
`cf_returns_not_retained` win over the name. `CFRetain`, `CFRelease`,
`CFAutorelease` and each `...Retain` or `...Release` of one CF type are not
bound: they are ARC's to call, and one called by hand would release what ARC
still holds. A function that takes ownership of an argument, `cf_consumed`,
is not bound either.

In a struct, behind a pointer, and given to a callback, a CF type is its
struct's pointer, `__CFString*`, which owns nothing.

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
- **A type from a framework not generated** -- CloudKit's, Intents' -- named
  in the reason.
- **A variadic function pointer**, which a delegate cannot be.
- **A `#define` that renames an extern**, which an extern cannot be given a
  second name to be, or that computes a string from others.
- **Apple's packed simd types**, aligned to a lane rather than to the vector,
  which no Stainless vector is.
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
and every bound enumerator's and integer macro's value against what clang
says -- 62,132 checks -- built for the target the suite runs as. Each
framework's checks are compiled with that framework's headers alone, a file
each: every framework's headers compile by themselves, and not all of them
together. The macOS lane runs it on Apple silicon and the Rosetta lane as
Intel code.

[tests/cases/macos-bindings-runtime](../../tests/cases/macos-bindings-runtime),
generated too, asks the Objective-C runtime for every bound class and every
message a class is declared to answer -- about 67,000 checks -- skipping what
appeared in a later macOS than the one running, and asking what one target
alone binds on that target alone. It loads every framework first, since a
program links only what it reaches. A message counts as answered when the
class or one derived from it answers it: an abstract class's `alloc` may make
a private subclass, as Metal's descriptors' does. A subclass is read, not
asked, so no class's `+initialize` runs.
[unanswered.txt](unanswered.txt) lists what the headers declare and the
runtime answers nowhere -- an informal protocol on `NSObject`, a method
nothing implements -- each with why; the case does not ask those.

[tests/cases/macos-bindings-objc](../../tests/cases/macos-bindings-objc) is a
program over the bindings: Foundation, a block, AppKit's category on
`NSString`, an `extern` string constant and Core Foundation's ownership.

[samples/macos/window.sl](../../samples/macos/window.sl) is a window: a view
defined in Stainless that draws itself with `NSBezierPath`, an application
delegate, and `--screenshot out.png`, which draws the view into a bitmap the
way AppKit draws it on screen and writes it as a PNG.

### Regenerating

```
tools/bindgen.sh          # on a Mac; about 26 minutes and 14 GB on an M4
```

The generator compiles each framework's headers, its subframeworks' included,
as Objective-C for `arm64-apple-macosx13.0` and `x86_64-apple-macosx13.0`
with `-ast-dump=json`, and keeps the declarations whose header is in the
framework. Every framework is read before any is written: a class one
framework names only with `@class` is defined by another, which may name the
first. A declaration is written by the framework whose header holds it, from
whichever framework's headers included it: IOKit's `usb/` headers are only
included by IOUSBHost's. A Core Foundation type several frameworks typedef,
as `IOSurfaceRef` is, is declared once, by the first. What the dump does not say -- whether `@class X;` is a definition,
whether a protocol's method follows `@optional` -- is read from the header's
line. A `#define` is asked of clang in the same translation unit, as
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
