<sub>[Stainless](../README.md) &rsaquo; Building and internals</sub>

# Building and internals

How to build the compiler, how it is tested, and what it is made of. For the
layout and calling-convention rules the emitter implements, see
[abi.md](abi.md).

---

## Building and testing

Requires the [.NET 10 SDK](https://dotnet.microsoft.com/download) and
[LLVM/clang](https://llvm.org) — `winget install LLVM.LLVM` on Windows,
`apt install clang` on Debian and Ubuntu.

```
dotnet build Stainless.slnx
dotnet run --project tests/Stainless.Tests      # 352 end-to-end tests
dotnet test tests/Stainless.UnitTests           # 1,337 compiler unit tests
```

The two suites ask different questions. An end-to-end case compiles, links and
runs a program, which proves the whole pipeline and takes a fifth of a second;
a unit test asks the front end alone — what did the lexer make of this, where
exactly does this error point, which registers does this struct travel in —
and takes a millisecond, so it can be asked by the hundred.

**A third question is what the compiler does with a program nobody wrote.**
Both suites hold programs that were meant to compile or meant to fail, and
neither holds the half-typed, truncated and nonsensical ones an editor hands a
compiler all day. [tests/Stainless.Fuzz](../tests/Stainless.Fuzz) makes those:

```
dotnet run --project tests/Stainless.Fuzz -- fuzz --minutes 10
dotnet run --project tests/Stainless.Fuzz -- replay     # which findings still fail
dotnet run --project tests/Stainless.Fuzz -- repro file.sl
```

It mutates every test case, sample and standard library file a token at a time
— deleting, repeating, swapping, nesting seven hundred deep — and compiles each
mutant through parse, bind and emit in process, stopping wherever the driver
would. A compiler may reject anything; it may not throw, overflow its stack,
run forever, or report a span that is not in the file, and any of those is kept
under `%TEMP%/stainless-fuzz/crashes`, one directory per distinct failure, with
the input shrunk to what still fails the same way.

Each worker is a process rather than a thread, because a stack overflow ends a
.NET process whatever handler is installed and a loop cannot be interrupted, so
the supervisor keeps the input a worker was compiling when it died or went
quiet. It is not coverage-guided: that would mean instrumenting the compiler
assembly, and keeping any mutant that makes the compiler report something new
has been enough to get past the parser. It does not link or run anything, so
it finds crashes and not miscompilations. Its first five minutes found two
dozen crashes the suites had not, and a fixed one is pinned by an ordinary case
like any other bug — the fuzzer's findings directory is not a test suite.

**Both Windows and Linux are tested.** 352 cases, of which 13 are
Windows-only and 2 are Linux-only, so Linux runs 339 and Windows 350, each
skipping the other's. A case whose *subject* differs by platform — `Path.Join` writes a
different separator, and `\x` is rooted on one and an ordinary name on the
other — carries an `expected.linux.txt` beside its `expected.txt` rather than
having the difference argued away.

Eleven of those cases are real 32-bit binaries, built and run on both systems, and
six are built for ARM64 and not run: there is no ARM64 machine here, so they
stop at an object file LLVM verified and lowered, with their signatures pinned
against clang's. Building 32-bit on Linux needs the development half of the
multilib packages, which is what
[tests/linux-x86.Dockerfile](../tests/linux-x86.Dockerfile) is for.

macOS is not tested. Nothing in the compiler is Windows-only and the runtime's
`#ifdef`s have a POSIX branch that Linux exercises, so it is likely close; the
constants in `bindings/linux` are Linux's and would not port, and that is
stated where they are.

`STAINLESS_CLANG` names the clang to use and always wins. Failing that the
compiler takes the first on `PATH`, then tries `C:\Program Files\LLVM\bin` and
its `(x86)` sibling on Windows, or `/usr/bin/clang` and `/usr/local/bin/clang`
elsewhere. `llvm-rc` is looked for beside whichever clang was found, because it
ships in the same directory.

---

## The pipeline

```
  .sl sources
      |
      v   Lexer -> Parser                       one file at a time, no #include
   syntax trees
      |
      v   Binder, in eleven whole-program passes:
      |     1. declare modules        7. compute C-compatible layouts
      |     2. declare types          8. check what crosses a language boundary
      |     3. resolve imports        9. check bodies
      |     4. resolve signatures    10. order and check static initializers
      |        and field types       11. check whatever those instantiated
      |     5. check that classes implement what they claim
      |     6. fold attributes to constants
      |
      |   A referenced library's declarations are loaded before pass 1, so a
      |   module from a binary is named exactly like one from source.
      |
      |   Nothing may depend on declaration order, so every name in the
      |   program is known before any body is checked. That single rule is
      |   what lets header files go away.
      v
   bound tree  (fully typed; ARC and ABI decisions already made)
      |
      v   LlvmEmitter, with the classifier for the target's ABI
   textual LLVM IR
      |
      v   clang
   native .exe
```

| Component | Role |
|---|---|
| [Syntax/Lexer.cs](../src/Stainless.Compiler/Syntax/Lexer.cs) | tokens, and `#if` deciding which of them exist |
| [Syntax/Parser.cs](../src/Stainless.Compiler/Syntax/Parser.cs) | recursive descent + precedence climbing |
| [Binding/Binder.cs](../src/Stainless.Compiler/Binding/Binder.cs) | the eleven passes; one partial class over `Binder.*.cs`, a file per area — bodies, calls, closures, conversions, generics, inheritance, layout |
| [Binding/TypeSystem.cs](../src/Stainless.Compiler/Binding/TypeSystem.cs) | types and C-rule layout |
| [Binding/TargetPlatform.cs](../src/Stainless.Compiler/Binding/TargetPlatform.cs) | what `--target` and `--abi` parse to, and the host's defaults |
| [Binding/EmbeddedFile.cs](../src/Stainless.Compiler/Binding/EmbeddedFile.cs) | what an `[Embed]` static holds: which sections a target already owns, and the assembly the object is written as |
| [Binding/Builtins.cs](../src/Stainless.Compiler/Binding/Builtins.cs) | `String`, `Utf16String`, `[Flags]`, the bit instructions `Standard.Bits` puts names on, and the lookup that finds the rest in the standard library rather than declaring it |
| [Binding/Mangler.cs](../src/Stainless.Compiler/Binding/Mangler.cs) | symbol names |
| [Binding/CppMangler.cs](../src/Stainless.Compiler/Binding/CppMangler.cs) | C++ symbol names, in the Itanium and Microsoft schemes |
| [Binding/MetadataLoader.cs](../src/Stainless.Compiler/Binding/MetadataLoader.cs) | symbols for a referenced library, from its metadata |
| [Emit/Win64Abi.cs](../src/Stainless.Compiler/Emit/Win64Abi.cs) | struct passing on Win64: register, `byval`, or `sret` — it asks only how big a struct is |
| [Emit/SysVAbi.cs](../src/Stainless.Compiler/Emit/SysVAbi.cs) | System V AMD64, which asks what is *in* a struct and cuts it into eightbytes |
| [Emit/X86Abi.cs](../src/Stainless.Compiler/Emit/X86Abi.cs) | 32-bit x86, where every struct travels on the stack and the two systems differ on returns |
| [Emit/Aapcs64Abi.cs](../src/Stainless.Compiler/Emit/Aapcs64Abi.cs) | ARM64 — one classifier, because Microsoft's ABI and ARM's agree about every shape asked |
| [Emit/LlvmEmitter.cs](../src/Stainless.Compiler/Emit/LlvmEmitter.cs) | IR, retain/release insertion, metadata tables; partial over `LlvmEmitter.*.cs`, and where the four classifiers above are chosen between |
| [Emit/DebugInfo.cs](../src/Stainless.Compiler/Emit/DebugInfo.cs) | what `-g` writes for a debugger |
| [Emit/CHeaderWriter.cs](../src/Stainless.Compiler/Emit/CHeaderWriter.cs) | the C header for a shared library |
| [Emit/MetadataWriter.cs](../src/Stainless.Compiler/Emit/MetadataWriter.cs) | the module metadata a Stainless consumer binds against |
| [Emit/DocWriter.cs](../src/Stainless.Compiler/Emit/DocWriter.cs) | the reference pages `stainless doc` writes from `///` blocks |
| [Driver/ModuleMetadata.cs](../src/Stainless.Compiler/Driver/ModuleMetadata.cs) | what that metadata contains, and how it is read back |
| [Driver/ProjectFile.cs](../src/Stainless.Compiler/Driver/ProjectFile.cs) | `stainless.json`, and refusing a field it does not know |
| [Driver/PackageResolver.cs](../src/Stainless.Compiler/Driver/PackageResolver.cs) | resolving dependencies, with [PackageLock.cs](../src/Stainless.Compiler/Driver/PackageLock.cs) and [Digest.cs](../src/Stainless.Compiler/Driver/Digest.cs) for the lock and the layout fingerprint |
| [Driver/Toolchain.cs](../src/Stainless.Compiler/Driver/Toolchain.cs) | finding clang and `llvm-rc` |
| [runtime/](../runtime/) | the whole runtime, split by feature |
| [stdlib/](../stdlib/) | the standard library, written in Stainless: a folder per module, a file per public type |

## Why textual IR

Emitting `.ll` text rather than calling the LLVM C API means the compiler has no
native dependency, builds anywhere .NET does, and produces output you can read
and diff. `stainless emit-ir hello.sl` prints it.

## Why ownership works the way it does

Stainless uses **borrowed parameters and owned returns**, the same choice Swift
makes, because it removes most retain/release traffic: passing a reference to a
function costs nothing. Locals and fields own their references; assigning to one
retains the new value *before* releasing the old, so self-assignment is safe.
A parameter the body *writes to* is the one exception — it is retained on entry
and released on exit, because otherwise its store would release a reference the
caller still owns.

---

<sub>[&larr; README](../README.md) &nbsp;&middot;&nbsp;
[ABI notes &rarr;](abi.md)</sub>
