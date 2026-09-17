<sub>[Stainless](../../README.md) &rsaquo; [Language specification](index.md)</sub>

# 10. Conditional compilation

Some code is only for one platform, and some is only for a build that asked for
it. Stainless chooses between them the way C# does: with directives, evaluated
while the file is being read.

```csharp
#if WINDOWS
extern "C" void* VirtualAlloc(void* at, nuint size, uint type, uint protect);
#elif UNIX
extern "C" void* mmap(void* at, nuint size, int prot, int flags, int fd, long offset);
#else
#error this platform has no page allocator here
#endif
```

**A branch that is not taken is never lexed.** So it need not parse, need not
resolve, and cannot be broken by a change made somewhere else — which is the
whole reason for choosing this early rather than in the binder. A branch for a
platform you have never built on is text until the day it is compiled.

**There is no macro, no textual substitution and no `#include`.** A name always
means itself, and a declaration is still found without a header. That is the
part of "no preprocessor" that mattered; `#if` was never what made C headers
what they are.

**The directives** are `#if`, `#elif`, `#else`, `#endif`, `#define`, `#undef`,
`#error`, `#warning`, `#region`, `#endregion` and `#pragma`. Anything else is an error
rather than something to be ignored. A directive must begin its line, and may be
indented; groups nest.

**A condition** is a name, `true`, `false`, `!`, `&&`, `||` and parentheses — the
same grammar C# has, minus `==` and `!=`, which nothing needs. **A name nobody
defined is false**, so a condition may test for something this build has never
heard of.

**`#define` and `#undef` take one name** and must come before the first
declaration in the file, as in C#: a symbol whose meaning changed halfway down
would make the lines above and below it disagree. They affect their own file
only.

**The symbols that describe the target are always defined:**

| Symbol | When |
|---|---|
| `WINDOWS`, `LINUX`, `MACOS`, `FREEBSD` | the operating system — still the host's, since `--target` does not change it yet |
| `UNIX` | any of the above but Windows |
| `X64`, `ARM64`, `X86` | the architecture being built for, which `--target` does change |
| `STAINLESS` | always |

Everything else comes from `-D` on the command line:

```
stainless build src -D FASTMATH -D TELEMETRY
```

There is deliberately no `DEBUG` among the built-ins. What it ought to mean is
the programmer's business, and inferring it from an optimisation level would be
a rule nobody asked for.

`#pragma` is the one directive that is not about choosing a branch; it is
covered in [§8.6](08-interop-libraries.md#86-linking-a-platform-library).

A whole file may be guarded, which is how a platform binding is written:
[bindings/win32](../../bindings/win32) declares its `module` and then wraps
everything else in `#if WINDOWS`, so on any other platform those modules exist
and are empty rather than failing to build. A program that imports one and
guards its own uses compiles everywhere.

---

<sub>[&larr; Statements and expressions](09-statements-expressions.md) &nbsp;&middot;&nbsp; [Contents &rarr;](index.md)</sub>
