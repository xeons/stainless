<sub>[Stainless](../README.md) &rsaquo; What is implemented</sub>

# What is implemented

Where the compiler actually is, as against what the
[language specification](spec/index.md) describes. The spec says what the
language is meant to be; this page says how much of it runs.

What is being worked on next, and the known bugs, are in
[TODO.md](../TODO.md).

---

## What works today

Everything below is covered by
[the test suite](../tests/cases), and this list is only as current as the
last person to edit it -- the suite is the authority.

- Modules like C# namespaces: several files may share one, imports are per file,
  `public` exports and an unmarked declaration is module-wide
- Aliases, qualified names without an import, full order independence
- `string` as a second spelling of `String`, declared as an alias in the
  auto-imported `Standard.Text`, so it needs no import and costs nothing
- Type aliases: `using Handle = void*;`, module-level, public or not, naming
  another alias or a type from another module. An alias is the type it names, so
  it costs nothing and converts nothing; a ring of them is refused whether or
  not anything uses it
- Opaque struct types: `public struct HWND__;`, C's incomplete type, declared
  here and laid out somewhere else. A value of one cannot exist and a pointer to
  one is a distinct type, so handles are told apart at no run-time cost at all.
  The generated C header declares the tag and typedefs the alias, exactly as C
  would write it by hand
- Bit-fields: `public uint Kind : 4;` in a struct or a union, with the width a
  constant from one to the width of the declared type. Both C ABIs are
  implemented — Microsoft opens a new storage unit when the declared type's size
  changes, Itanium packs across — and `--abi` chooses, defaulting to the host's.
  A signed field sign-extends from its own width; writing one leaves its
  neighbours alone; one has no address, so no `ref` to it
- Both struct conventions, chosen by the same `--abi`: Win64 asks only how big
  a struct is, and System V AMD64 asks what is in it — cutting it into
  eightbytes and passing each in an integer or an SSE register, so
  `{ double; int; }` takes one of each and `{ float; int; }` takes one. Every
  shape was checked against clang built for the matching target
- **32-bit x86**, with `--target x86`: a four-byte pointer, and every header
  counted in words rather than in eights. Every struct travels on the stack,
  because there are no argument registers to classify into; returns are where
  the two systems part company, and Windows returns a struct of 1, 2, 4 or 8
  bytes in a register where i386 System V returns every struct in memory. Both
  systems are built *and run* by the suite, as real 32-bit binaries
- **ARM64**, with `--target arm64`, and one classifier for both systems because
  Microsoft's ARM64 ABI and ARM's agree about every shape asked. A struct whose
  members are all the same floating-point type, four or fewer of them and no
  padding, travels in one SIMD register each however big it is; everything else
  of sixteen bytes or less goes in one or two general registers, and everything
  larger is a pointer to a copy. Nothing here has *run* an ARM64 binary: there
  is no such machine and no ARM64 C library to link against, so the cases stop
  at an object file that LLVM verified and lowered, with the signatures pinned
  against clang's
- **Calling conventions** a declaration can name: `__cdecl`, `__stdcall`,
  `__fastcall` and `__vectorcall`, written after the linkage string and
  applying to one declaration or to a whole `extern "C"` block. On x64 only
  `__vectorcall` differs, and ARM64 has one convention at all; on x86 each
  decorates the linker name with what its arguments occupy — `_f@8` for
  `__stdcall` — which is what makes a caller and a callee disagreeing about the
  count a link error rather than an unbalanced stack. Decoration is Microsoft's
  and stops where PE does: an i386 ELF `__stdcall` gets the convention and the
  plain name, which is what gcc has always done
- `[Packed]` and `[Align(N)]`: no padding at all, and a raised alignment. Both
  are rules about layout rather than library features, so neither needs an
  import; they combine, N is a power of two capped at 16, and both apply to a
  `struct` and nothing else. The generated C header states them with
  `#pragma pack` and an `SL_ALIGN` macro, and the sizes, alignments and offsets
  are checked against the target's own C compiler
- `struct` with fields, methods and constructors; exact C layout; value copy
  semantics. `new Point(3, 4)` allocates nothing: the constructor runs over the
  slot the expression needed, zeroed first, so a constructor adds no header and
  no hidden field. One taking no arguments is refused, because `Point value;`
  runs nothing and the zero value is what an unconstructed struct is. A struct
  may hold a reference, and copying one then retains what it holds — the cost
  is that it is no longer a value C can be handed, which the compiler checks at
  every `extern "C"` and `export "C"`
- `union`: C's, every member at offset zero, with the size and alignment C
  computes. No member may hold a counted reference, because a union does not
  record which one is live. `[Packed]` and `[Align]` apply as they do to a
  struct, and a generated C header writes it as a C `union`, member for member
- `variant`: a value that is exactly one of its cases and says which. A tag
  plus the widest case's payload, with the cases overlapping, so nothing
  allocates and the size is the maximum rather than the sum. Cases carry named
  fields; `v.Case` asks the tag; a payload is readable only where the compiler
  has already established its case. `switch` over one names cases rather than
  values, binds a payload with `case Circle c:`, needs no `default` once every
  case is covered, and counts as a way out of the function when it is.
  Reference counting consults the tag, so a case may hold a `String`, a class
  or an array and only what is really there is ever counted. Generic variants
  monomorphize like anything else
- `Result<T, TError>`: the language's answer to an exception, and now an ordinary
  variant — `Ok(T Value)` and `Fail(TError Error)` — with no machinery of its own.
  A call that succeeds allocates nothing; `Ok(x)` and `Fail(e)` are written
  without type arguments and take their type from what they are returned or
  assigned into, the way a lambda does. `Value` and `Error` are readable only
  where the compiler has already seen which case is there — after `if (r.Ok)`,
  in the arm of a ternary, after an early `if (!r.Ok) { return ...; }`, or in a
  `switch` arm — and `GetValueOrDefault(fallback)` needs no proof because it supplies one
- Flow narrowing, for a variant's case and for `C?` alike: `if (x != null)`
  makes `x` a `C`, through an `if`, a `!`, `&&`, `||`, a ternary, an early
  return and a `switch`. Only for a local or a parameter, and never for a
  `weak C?`, which may die between the check and the use; an assignment takes
  the proof away, and so does one anywhere in a loop body
- `is` with a name — `if (node.Payload is Circle c)`, for a variant's case or a
  class — which is how a field or a call result gets at what a test found. The
  value is evaluated once and the name is in scope where the test succeeded.
  Over a `C?` it asks about the null and the class at once, so
  `if (node.Next is Node n)` is the narrowing a field could not have
- `as`, which asks what `is` asks and answers with a value: `x as C` is a `C?`,
  so the answer can be passed on, stored, or given a fallback --
  `(shape as INamed)?.Name() ?? "anonymous"`. The value is read once, the arm
  the test allows is that same pointer with no second check, and a conversion
  that cannot fail gets no test at all. What could only ever be null is a
  mistake rather than a null (SL0612), and a COM interface is refused because
  `QueryInterface` is a call that would be made twice
- `class` with fields, constructors, destructors, methods; ARC with correct
  nested destruction
- `record`: a class written as its constructor. The positional parameters
  become get-only properties and the constructor that fills them, and the type
  gets `Equals`, `GetHashCode`, `==`, `!=` and the `IEquatable`/`IHashable` those
  satisfy -- so a record is a dictionary key with nothing said, which is most
  of what the form is for. `point with { Y = 9 }` makes a changed copy,
  evaluating its target once. There is no generated `ToString`, because the
  language has none for any type, and no `record struct`, because what makes a
  record a key is the two interfaces it declares and a struct implements none
- Single inheritance, the C# model: `virtual`, `override`, `abstract`,
  `sealed`, `protected`, `base.M()`, and `base(...)` chaining written either
  after the parameters as C# writes it -- `Square(double side) : base(4)` --
  or as the first statement of the body. A virtual call is
  three constant-offset loads and an indirect call — one fewer than an interface
  call, because there is no interface id to look up. Fields are laid out after
  the base's, destructors chain derived-first, interfaces and their tables are
  inherited, and an upcast emits no instructions at all
- `com interface` and `com class`: COM's binary contract, which is a pointer
  to a vtable pointer and needs no operating system, so both work on every
  platform. ARC drives `AddRef` and `Release`, `is` and a cast are
  `QueryInterface`, and `[Guid("...")]` folds to a constant `iidof` names. A
  com class presents vtables from an ordinary object through tear-offs, one per
  interface, each with the distance back that lets a `Release` find the header.
  Every slot is `__stdcall` on x86 — part of the contract rather than a Windows
  detail — which a `com interface` does not have to say, because the convention
  is stamped on when its table is numbered. `[NoUnknown]` describes the vtable a
  C library hands out that is not COM — XAudio2's voices — so its first method
  is slot 0 and ARC counts nothing through it; the cost is no `[Guid]`, no
  `QueryInterface` and no cast (SL0622, SL0623, SL0624)
- **A COM server.** `[Guid("...")]` on a `com class` is a CLSID, the compiler
  gathers every class carrying one into a factory table, and
  `Com.GetClassObject` answers it with an `IClassFactory` — so a `--shared`
  build exporting `DllGetClassObject` is an in-process COM server that C++
  activates and uses. Activation passes no arguments, so an activatable class
  needs a constructor taking none (SL0611). `DllCanUnloadNow` answers from a
  module-wide count of live com class objects, so it says S_FALSE while one is
  held and S_OK once none is — the count is kept only where something can be
  activated, so a program that hosts nothing emits none of it.
  [samples/com](../samples/com) is the server, a C++ host and the destructor
  running between the host's `Release()` and its next line
- **A module definition file, where the names need one.** On 32-bit x86 a
  calling convention decorates a symbol, so `export "C" __stdcall` is
  `_DllGetClassObject@12` in the object file — and Windows' loader looks up
  `DllGetClassObject`. The compiler writes a `.def` naming those exports under
  the names their source declared, which is what every C++ COM server does and
  what keeps "the export table is exactly the `export \"C\"` functions" true on
  x86 as well as x64. Written only where a name would otherwise be wrong, and
  `--def` supplies one by hand — an alias, an ordinal, a data export — which is
  added to the compiler's own renames rather than replacing them
- `x is T` and a checked `(T)x`, for classes and interfaces alike. `is` answers
  false for null, so a test through a `C?` asks about null and about the class
  at once; a cast that does not hold names what the object really is and ends
  the program, there being no exception for it to throw
- Properties, on classes, structs and interfaces: `{ get; set; }` with a
  compiler-generated backing field, `{ get; private set; }`, get-only ones a
  constructor fills in, and written accessors with block or `=>` bodies. They
  lower to a pair of ordinary methods, so an interface property dispatches like
  any other member
- `extern "C"` and `export "C"`, including variadics and structs by value in
  both directions
- `extern "C++"` and `export "C++"` for free functions, in both directions and
  with no shim between: the signature is mangled the way the target's compiler
  mangles it, in the Itanium scheme for gcc and clang or Microsoft's for MSVC.
  A namespace is written on the declaration — `extern "C++" double
  geometry::Area(double, double)` — and decides the linker name and nothing
  else. Both schemes are checked against clang's own output for the same
  signatures. C++ *classes* are not reachable yet; that needs object and vtable
  layout, and an answer for exceptions crossing a boundary nothing unwinds
- `asm (in rcx = n, out rax = r) { ... }` — inline assembly as a statement, in
  Intel syntax on x86 and x64 and ARM's own on ARM64, lowered to one LLVM
  inline-assembly call. Registers are checked against the target, a value
  narrower than its register is extended by its signedness, and every block is
  declared to clobber what a C call may, so there is no list to get wrong. Run
  on Windows x64, Linux x64 and 32-bit x86 on both, with a test that fails if
  the clobbers are; ARM64 is built to an object file and pinned as text. A
  mistake in the text is reported on its line by the assembler, as SL0723
- Win64 struct ABI: register coercion, `byval`, `sret`
- `if` / `while` / `for` / `foreach` / `break` / `continue` / `return`, recursion
- `switch` over integers, `char`, `bool`, enums, `String` and variants, with
  stacked labels and no fall-through. An ordinal switch is one LLVM `switch`, so
  a jump table is LLVM's decision rather than the programmer's; `break` belongs
  to the switch while `continue` passes through it to the enclosing loop
- `parallel { place = spawn f(x); }` — a fork-join scope whose closing brace
  waits, so a job writes its result straight into the parent's local; and
  `for parallel`, which splits a counted loop across the pool. `spawn` prefixes
  the call rather than the statement, because the call is the part that forks;
  `parallel` alone always means the scope
- `Thread` and `Future<T>` for work no lexical scope brackets — a listener, a
  background writer, a result returned from the function that started it. Both
  take a lambda, and `Future<T>.GetResult` blocks, which needs no `async` anywhere
- `static` as C# means it: fields, methods, properties, static constructors and
  `static class`, on a module or on a type, mutable or `readonly`. Storage is
  initialized before `Main` in an order the compiler computes from the
  dependency graph — no lazy guard, and a compile error on a cycle. A static
  method is what a fallible factory is written as, since it can use a private
  constructor and a constructor cannot report why it failed
- `threadsafe`, a word on a class, struct or interface saying that operations
  on it synchronize themselves. Anything crossing a thread that is not that,
  plain data, a `String` or an array of plain data draws a warning at the
  `spawn`, the `for parallel` capture, or the static that would share it --
  a warning rather than a refusal, because the word is an assertion no compiler
  can check, and refusing would leave someone who knows better with nothing to
  do but write it untruthfully. `where T : threadsafe` is the strict form, and
  there it is an error, because the library author asked
- Patterns, in a `case` label and in a `switch` expression: a constant, a
  variant's case, a type, a range (`> 100`), `or`/`and`/`not`, `_`, and a
  `when` on any of them. Each becomes the `bool` that asks it -- a comparison,
  a tag test or an `is` -- so there is no matching machinery underneath. A
  switch whose labels are all constants is still one LLVM `switch` and a jump
  table; one with a pattern in it is a chain of tests
- `switch` as an expression: `n switch { < 0 => "negative", _ => "large" }`,
  which must be exhaustive (SL0620) because it has to produce a value and there
  is no exception to throw at a value that matched nothing. It lowers to the
  value held in a name and a conditional per arm
- A lambda with written parameter types has a type of its own, so `var doubled
  = (int x) => x * 2;` is a `closure int(int)` -- cached by signature, so two of
  a shape are one type, and a declared `closure` of that shape is
  interchangeable with them
- Field and property initializers: `int Width = 80;` and `int W { get; set; }
  = 80;`, run at the head of every constructor in declaration order. A class
  that declares no constructor is given one to run them in; a constructor that
  chains to `this(...)` does not run them again; and an initializer may not read
  the object it belongs to (SL0617), because it runs before the constructor's
  body and would be reading zeroes. A value type has no moment to run one at and
  refuses it
- Object and collection initializers: `new Panel { Title = "readme" }` and
  `new List<int> { 1, 2, 3 }`, lowered to the construction held in a name, a
  write or an `Add` per entry, and the name. `Add` is found by name rather than
  by interface, as `foreach` finds `GetEnumerator`; named and bare entries may
  not be mixed (SL0618)
- Conversion operators: `public static implicit operator Money(long)` and its
  `explicit` twin, written inside one of the two types they are between. The
  word decides whether a cast has to be written, which puts a declared type into
  the same system the built-in conversions are in. One conversion and no chain:
  the value is exactly what the operator takes, except for a literal, which
  adopts the source type as it does anywhere else. What is refused is anything a
  reader could not find from the two types, and anything the language already
  answers (SL0615)
- Default values on parameters: `void Draw(String text, int width = 8)`, filled
  in at the call from the declaration the caller can see. A constant is what one
  may be (SL0613), the ones that may be left out are the tail of the list, and
  exactly one declaration may give it -- an `override` may not restate a default
  and neither may a method beside the interface method it implements (SL0614),
  because a call reads the static type's declaration and two values would make
  the same line mean two things. They cross a library boundary as the value they
  folded to
- Full operator set with C# precedence, short-circuit `&&` and `||`, and the
  conditional `a ? b : c`. The arithmetic C leaves undefined is defined here:
  a shift count is reduced modulo the operand's width as in C#, so `1 << 40` is
  256 rather than garbage, and an integer division by zero — or the one signed
  division that overflows — aborts the way an out-of-range index does, rather
  than being folded to whatever the optimiser likes. A divisor that is zero at
  compile time is an error instead. Aborting writes a line to standard error
  and ends the process, after flushing everything the program has written, so
  the output that led up to the failure is there to read
- `var`, `const`, explicit locals, compound assignment. A `const` may also be a
  member of a type — inlined like a module-level one, reached as `Type.Name`
  from outside and inherited down a class chain — and a `--shared` library may
  carry one, since there is nothing to initialize
- `String`: UTF-8, immutable, reference counted, `+` and `==`, zero-copy
  `ToPointer()`, `ToUtf16()`, and literals that never allocate. UTF-16 converts
  back with `ToText()` or, from a buffer a platform API filled, with
  `Text.FromUtf16`; anything malformed becomes U+FFFD in both directions, so a
  `String` is UTF-8 by invariant
- A string API to go with it: `StartsWith`, `Contains`, `IndexOf`,
  `LastIndexOf`, `Substring`, `SubstringBefore`/`SubstringAfter`/`SubstringAfterLast`, `Trim`, `Replace`,
  `Repeat`, `PadLeft`/`PadRight`, `Split`, `SplitLines`, `Join`, `CompareTo`,
  the ASCII case pair, and `GetCodePointAt`/`SkipCodePoint` for walking the text
  properly. All of it written in Stainless rather than C, because a type may be
  declared more than once inside its own module and `String`'s second
  declaration is `stdlib/Text/String.sl` — which is also why `Split` can
  return a `String[]` when the runtime cannot allocate one
- A type may span declarations, the way a module already spans files. The first
  says what the type is — its kind, its fields, what it derives from — and a
  later one adds behaviour and nothing else. No `partial` keyword, because
  there is nothing for it to prevent
- `StringBuilder`: appending, reading (`GetByteAt`, `IndexOf`) and editing
  (`Insert`, `Remove`, `TruncateTo`, `ReplaceAll`). It hands out no pointer,
  unlike `String`: its bytes move as it grows, so one would dangle at the next
  append
- `char`, `char16` and `char32`: one UTF-8 code unit, one UTF-16 code unit and
  one Unicode scalar. Three encodings rather than three widths, so none becomes
  another without a cast, and a character literal is one scalar that takes the
  narrowest of the three holding it whole. `Utf16String.ToPointer()` is a
  `char16*`, which is what makes handing a wide API the wrong 16-bit pointer a
  compile error
- `T[]`: counted arrays, always bounds checked, elements released with the array
- Array literals: `[1, 2, 3]`, taking their type from where they are going — a
  `T[]`, a `T[N]` of matching length or a `T[:]` — or from their own elements
  when nothing else says, so `var xs = [1, 2, 3]` needs no type written out
- `T[N]`: an inline fixed-size array, which is C's and not C#'s — it *is* its
  elements rather than a reference to them, so a struct holding one is exactly
  as wide as the C struct it mirrors. The length is part of the type, so
  `.Length` is a constant and an out-of-range constant index is a compile error
  rather than an abort. `WIN32_FIND_DATAW` is 592 bytes here as it is there
- `T[:]`: slices. `a[1:4]`, `a[3:]`, `a[:2]` and `a[:]` over an array or another
  slice, with half-open bounds; three words, so nothing allocates. A view rather
  than a copy — writing through one writes the array, and an index is checked
  against the slice's own length. Slicing a slice narrows it rather than nesting.
  It holds the array it came from, so it cannot dangle: what it points into is
  alive for as long as it is. An array converts to a slice of the whole of
  itself implicitly, and `foreach` walks one like an array
- Generics: generic classes, interfaces, functions and methods, monomorphized,
  with inference at call sites and constraints: an interface, a base class,
  another type parameter, `class`, `struct`, `new()` and `threadsafe`
- `enum`, strongly typed: a distinct type over an integer that never converts
  implicitly in either direction, with an optional underlying type
  (`enum Level : byte`)
- `[Flags]` enums: `|`, `&`, `^` and `~` on an enum whose members are bits,
  producing that same enum rather than its number, plus `HasFlag`. The marker
  needs no import, because it is a rule about enums rather than a library
- `ref`, `in` and `out` parameters: the caller's storage rather than a copy of
  it. `ref` is writable and `in` is not; `out` is writable and *must* be
  written, which is the promise that lets the caller pass a variable holding
  nothing. `ref` and `out` are written at the call as well as the declaration,
  must name storage, and are not converted; writing to an `in`, or passing one
  on as a `ref`, is refused. A call may declare the variable an `out` fills —
  `TryHalve(10, out var five)` — taking its type from the parameter. The mode is
  part of a signature, so overloads may not differ only in it and a class does
  not implement `ref int` with `int`. All three are a `T*` at the ABI, so
  `extern "C" double modf(double, ref double)` needs no shim, and a generated
  header writes them `T*`, `const T*` and `T*`
- Named arguments: `Draw(text, width: 3, center: true)`, after the positional
  ones. Each names a parameter, none twice, none left out, and the names take
  part in choosing an overload — which is what makes a four-`bool` call and a
  wide constructor readable
- `delegate`: a named function pointer, one word, C ABI compatible in both
  directions, and storable in a `struct`
- `closure`: a method **and the object it belongs to** — two words, what Delphi
  spells `of object`, and what a callback has to be to know anything.
  `counter.Add` and a capturing lambda are the same type and interchangeable;
  the receiver is kept alive by ARC for as long as the closure is; and `==`
  compares both words, so one is removable from a list of them. It costs
  nothing to support: a method already takes its receiver as argument zero, so
  a bound method pointer is the method's own address beside the object, and
  being two fields is what gives it layout, both ABI classifiers and reference
  counting without any of them being written for it
- `event`: several subscribers behind one name, in C#'s shape —
  `source.Changed += listener.OnChanged` and `-=` to take it off again, removal
  by closure equality so the right one goes. Raising calls every subscriber in
  the order they subscribed, and **only the declaring type may raise it**: from
  outside, those two operators are all there is, which is what separates an
  event from a public field of closure type. Two of C#'s sharp edges are filed
  off: raising an event nobody has subscribed to does nothing rather than
  throwing, so no `?.Invoke` anywhere, and a handler must return `void`, since
  with several subscribers there is no honest answer to what it returned. A
  raise reads the subscriber list before it starts, so a handler may subscribe
  or unsubscribe while it runs. Events cross a library boundary: a program
  subscribes to one declared in a library it has no source for
- Lambdas: `value => value * factor` becomes a generated class capturing **by
  value**, so it may outlive the scope that built it. What it is *seen* as is
  decided by what it is assigned to — a `closure`, a single-method interface,
  or, if it captures nothing, a `delegate`. A
  lambda written in a method reaches its object too — a field, a property,
  `this`, or a method called without a receiver. **Which of those copies is
  worth knowing**: a bare `factor` copies the value, `this.factor` captures the
  object and reads it live, and a method call does the same. A captured member
  that something else assigns is a warning (SL0610), because `if (busy)` in a
  handler reads as a live test and is not one
- `weak C?`: assignable, so a reference cycle can be broken. A weak reference
  costs the object nothing while it lives and reads back as `null` once it is
  gone, rather than as a pointer into freed memory
- `foreach` over arrays and over anything with a `GetEnumerator()`, plus
  `IEnumerable<T>` / `IEnumerator<T>` in `Standard.Collections`
- One runtime where two Stainless binaries meet: a program and the libraries it
  loads reach the same allocator, the same reference counts and the same stdio
  buffer, so an object made on one side and dropped on the other is counted once
  and output interleaves in the order it was written. It is a shared library
  built once and copied beside what uses it; a program with no such boundary
  keeps the copy compiled into it and stays a single file. `--runtime` overrides
  the choice, and a mismatch across a boundary is refused rather than left to
  misbehave
- Interfaces: several per class, dynamic dispatch, checked at compile time,
  inherited by a derived class along with everything else, and extending one
  another with free conversion to the base. A class may implement
  two instantiations of one generic interface — `IEq<int>` and `IEq<String>` —
  because each interface has its own dispatch table and the overloads land in
  different slots
- Overloading by parameter type, on methods as well as module-level functions;
  a return type alone does not distinguish two of them
- `Standard.Collections`: `List<T>`, `Dictionary<TKey, TValue>`, `HashSet<T>`,
  `Queue<T>`, `Stack<T>`, `LinkedList<T>` and `SortedList<TKey, TValue>`, plus
  `IComparable<T>`, `IEquatable<T>`, `IHashable`, `IReadOnlyList<T>`,
  `IList<T>`, `IEnumerable<T>` and `IEnumerator<T>`. Every container is
  array-backed — ARC cannot collect a cycle, so the linked list links by index
  rather than by reference — and every one of them walks itself when iterated
  rather than copying into a list first
- **`Sort` is a stable merge sort**, over a `T[:]` or an `IList<T>`, by
  `IComparable<T>` or by a `Comparison<T>` you pass. Stability is what lets a
  multi-key order be built by sorting twice. Alongside it: `Max`,
  `Min`, `IndexOf`, `RemoveFirst`, `RemoveWhere`, `Reverse`,
  `BinarySearch` and `FindLowerBound`
- **`x.F(y)` is `F(x, y)`** when `x` has no member `F`, which is what makes the
  library chain:

  ```csharp
  words.Where(w => w.ByteLength() > 1u).Distinct().OrderBy((a, b) => a.CompareTo(b)).ToArray()
  ```

  Uniform call syntax rather than extension methods: a module is a scope here,
  so a function need not be wrapped in a static class to exist and there is
  nothing a `this` modifier would add. A member always wins, so nothing a type
  declares can be shadowed by somebody else's function
- **Combinators**, over an array, a slice or any `IEnumerable<T>`: `Select`,
  `Where`, `Aggregate`, `Any`, `All`, `Count`, `Find`, `FirstOrDefault`,
  `FindIndex`, `ForEach`, `Take`, `Skip`, `Distinct`, `OrderBy`, `ToList` and
  `ToArray`, under the names LINQ gave them. Each takes a generic
  `closure` — `Func<T, TResult>`, `Predicate<T>`, `Action<T>`,
  `Fold<TAccumulate, TSource>`, `Comparison<T>` — so a lambda and a method
  that already exists are the same thing:

  ```csharp
  var adults = Where(people, p => p.Age >= 18);
  var names  = Select(adults, p => p.Name);
  long total = Aggregate(numbers, (long)0, (sum, n) => sum + (long)n);

  ForEach(lines, report.Note);        // a method bound to an object
  Sort(people, (a, b) => a.Age - b.Age);
  ```

  These were one-method interfaces until a closure could be generic, and the
  bound-method line is what that bought: an interface needs an object that
  implements it, so passing an existing method meant declaring a class whose
  only purpose was to carry it.

  Eager, not lazy: each returns a `List<T>`, because lazy chaining wants
  generators and the language has no `yield`
- **"Not there" is an `Optional`**, not a sentinel. `IndexOf`, `FindIndex`,
  `Find` and a dictionary's `map[key]` answer with one, so a length, a magic
  number or a crash never stands in for a miss. A value converts implicitly to
  the `Optional<T>` holding it, as it does to a `T?` in Swift and C#, which is
  what lets `map[key] = value` stay ordinary while `map[key]` stays honest
- Primitives, enums and `String` satisfy `IComparable<T>`, `IEquatable<T>` and
  `IHashable` without declaring it, so `Sort(numbers)` works on a `List<int>`
  and `Dictionary<String, V>` needs nothing extra
- `StringBuilder`: mutable text with amortised O(1) appends
- `Standard.Threading`: two layers. The structured one is `Mutex<T>` and its
  `Guard<T>` (the lock owns what it guards, and a destructor releases it),
  `Monitor<T>` with `Wait`/`Pulse`, `ReaderWriterLock<T>` with separate read and write
  guards, `AtomicLong`/`AtomicInt`/`AtomicBool`, and `TaskScope` for running
  `Job` delegates on the pool. The unstructured one is `Thread` itself
  (`Join`, `Detach`, and a destructor that joins), `Semaphore`,
  `ManualResetEvent`, `AutoResetEvent`, `CountdownEvent`, `Barrier`, `SpinWait`
  and `Threading.Sleep`/`Yield`/`CurrentId`. A `spawn`ed job may borrow the
  frame that spawned it; a `Thread` may not, and what it touches has to outlive
  it — see [docs/concurrency.md](concurrency.md) §11
- `Standard.Math`: the C library's floating point, plus `Abs`/`Min`/`Max`/
  `Clamp`/`Sign` overloaded across `int`, `long`, `nuint` and `double`,
  `IsNaN`/`IsInfinity`/`IsFinite`, `GreatestCommonDivisor` and
  `LeastCommonMultiple`. Counting and rotating bits is `Standard.Bits`, as it
  is `BitOperations` and not `Math` in .NET. A module is a scope, so
  `Math.Sqrt(x)` needs no static class
- `Standard.Concurrent`: `ConcurrentQueue<T>`, `ConcurrentStack<T>`,
  `ConcurrentDictionary<TKey, TValue>` and a blocking `Channel<T>`. Each owns its
  collection in a field and never hands out a reference to it, because a lock
  protects what it guards and not the reference *count* of what it guards
- `Standard.Process`: running another program, on both platforms.
  `RunProcess(program, arguments)` waits and captures; `Start` hands back a `Process`
  to wait on, poll or stop. **There is no shell** — the arguments are a list,
  so a `>` or a space in a filename is a character the child receives rather
  than something a shell acts on. A failure to *start* is a `ProcessError`; a
  program that ran and returned 1 is a `ProcessResult`, which is an outcome.
  Both streams are drained while it runs, because a pipe holds about 64KB and
  a parent that waits first would wait forever. `Signals.StartWatching()` notices Ctrl-C
  as a flag to read rather than a handler to run in
- `Standard.Env`: the command line, environment variables and the working
  directory. `Main(String[] args)` is the better way to read the arguments --
  a function that takes what it needs beats one that goes looking -- and
  `Env.GetArguments()` is for the code that is nowhere near `Main`
- `Standard.Time`: `DateTimeOffset` (a point on the wall clock) and
  `TimeSpan` (a length), both structs over one `long` of nanoseconds that
  declare the arithmetic to go with it -- `hour + minute`,
  `later - earlier` -- and are made by naming the unit,
  `TimeSpan.FromSeconds(30)`. Plus `DateTime` for the
  parts a person reads, ISO 8601 in both directions, and `Stopwatch` over the
  **monotonic** counter -- which is the only correct way to measure how long
  something took, because the wall clock can jump mid-measurement. The UTC
  calendar is computed rather than delegated, so dates before 1970 work on
  Windows too
- `Standard.Random`: xoshiro256**, seeded by you for a reproducible run or by
  the operating system for an unpredictable one. A class rather than free
  functions, because the state has to live somewhere and a hidden global one
  is what makes a program impossible to replay. `Random.FillSecureBytes` goes straight to
  the platform's cryptographic source, which is what a key or a token wants
- `Standard.IO`, `Standard.File`, `Standard.Directory`, `Standard.Path`:
  `IStream` with `FileStream` and `MemoryStream`, whole-file reads and writes,
  directory listing, and textual path handling. Failure is a returned value —
  a `Result<T, IOError>`, or a bare `IOError` where nothing is produced. Paths
  are UTF-8 and are widened to UTF-16 before they reach Windows.
  `Standard.Path` answers the platform's questions rather than one platform's:
  Windows reads both `\` and `/` apart and writes `\`, and everywhere else
  only `/` is a separator — a backslash there is an ordinary character a
  filename may contain, so treating `report\2026.csv` as two parts would be
  wrong rather than lenient
- `Standard.Net`: `TcpListener`, `TcpClient`, `UdpClient` and the `Socket`
  underneath them, the same on Windows and Linux. `TcpClient` is an `IStream`,
  so a reader written against a file works over a connection with nothing
  changed. Winsock and BSD sockets disagree about the handle, the errors, the
  close and the startup; all of that is in `runtime/socket.c` and none of it
  reaches a program
- `Standard.Encoding`: UTF-8, UTF-16 and UTF-32 in both byte orders, ASCII,
  Latin-1 and Windows-1252, behind an `IEncoding` a program can implement.
  Lossy by default, because `GetString` returns a `String` and a `String` is
  valid UTF-8 by invariant; `TryGetString` is the strict form and refuses an
  overlong sequence as well as a malformed one. `DetectEncoding` reads a byte order mark
- `Standard.Drawing`: raster images. `Image.FromFile` and `FromBytes` decode
  PNG, JPEG, BMP and GIF by sniffing the first bytes rather than the name;
  `Create` makes an empty one; lines, rectangles, ellipses, polygons, blits and
  pixels draw on it; `Encode` and `Save` write it back. GDI+ on Windows and
  libgd elsewhere, both loaded by name at the first call and neither linked, so
  a program that makes no image pays nothing and a machine with no imaging
  library answers `ImageError.NoBackend` rather than failing to link. Written
  in Stainless like the rest of the library: `delegate __stdcall` and the
  pointer-to-delegate cast are what a resolved symbol is called through. No
  text -- a font is where the two backends stop agreeing
- `Standard.Security.Cryptography`: the symmetric half, complete. MD5, SHA-1,
  SHA-256, SHA-384 and SHA-512, HMAC over any of them, PBKDF2, HKDF, AES in ECB,
  CBC, CFB and CTR, AES-GCM, the platform's entropy and a constant-time
  comparison, in `System.Security.Cryptography`'s shape with a `Result` where
  .NET throws. Every answer is pinned against a published test vector. Not
  public-key, which wants a constant-time bignum the library does not have
- `Standard.Media.Audio`: playing and recording interleaved PCM, and reading and
  writing WAV. WASAPI on Windows and ALSA elsewhere, both reached by name at the
  first device rather than linked, so a machine with neither answers
  `AudioError.NoBackend`. The Windows half has played and recorded; the ALSA
  half has compiled and never opened a device
- `Standard.Json` and `Standard.Xml`: each in two layers. A document that needs
  no type -- `Json.Parse` gives a `JsonValue`, a variant that is exactly one of
  the six things JSON has, and `Xml.Parse` gives an `XmlNode` -- and a mapping
  onto a `[Reflect]` type, where `Serialize` reads an object's fields and
  `PopulateObject` writes them. Reading fills an object the program made rather than
  allocating one, so a constructor has established the type's invariants before
  a single field is overwritten, and a field the document does not mention keeps
  what the constructor chose. Arrays and collections are left out of the
  mapping: the field tables record that a field is an array and nothing about
  its elements, so a type holding one wants the document layer
- `Optional<T>`, a variant in `Standard`: a value or none, for the types `T?`
  cannot describe. `C?` is a nullable reference and costs nothing, but a value
  type has no spare bit to be null with — so `nuint?` is refused and this is
  what `IndexOf` answers with instead of a magic number. Not a second meaning
  for `?`: a pointer for a class and a tagged pair for a value would have been
  two representations behind one spelling. It reads like Java's — `HasValue`,
  `IsEmpty`, `GetValue`, `GetValueOrDefault`, `Coalesce`, `Select`, `SelectMany`, `Where`, `InvokeIfPresent` —
  over machinery that is all variant: `if (found is Some at)` is what every one
  of them is written in terms of
- `OrderedDictionary<TKey, TValue>`: a dictionary that keeps the order its keys were
  added in, found by scanning rather than hashing. For wherever the order is
  part of the data — a parsed document read back the way it was written — and
  not for anything large enough for O(n) lookup to hurt
- `Standard.Text.FromDouble` writes the shortest text that reads back as the
  same number, and `Standard.Convert.ToDouble` is its correctly-rounded
  inverse, so a number survives being written and read
- `Standard.Convert`: base64 and base64url, hex, and integer and floating-point
  parsing in any radix from 2 to 36. Everything that can fail returns a
  `Result`, because there is no exception to throw and no `out` to fill
- `Standard.Text` (imported everywhere), `Standard.Ascii`, `Standard.Console`,
  `Standard.Reflection`
- `Standard.Bits`: `PopCount`, `LeadingZeroCount`, `TrailingZeroCount`,
  `RotateLeft`, `RotateRight`, `Log2`, `IsPowerOfTwo` and
  `RoundUpToPowerOfTwo`, over the target's own instructions. A rotate is
  defined for a count of zero, which the pair of shifts it replaces is not
- `Standard.Limits`: what each number type holds, named rather than spelled --
  `MaxInt`, `MinLong`, `MaxNUInt` and the rest, the pointer-width ones written
  per target
- `Standard.IO`'s readers and writers: `TextReader` and `TextWriter` with
  `StringReader`, `StreamReader`, `StringWriter` and `StreamWriter` under them.
  `StreamReader` decodes a buffer at a time through an `IDecoder` that keeps
  whatever character the buffer ended in the middle of, so it streams rather
  than reading the whole thing
- Raw pointers, `sizeof`, `alignof`, `offsetof`, `typeof`, casts, `new`, `this`.
  The three layout questions answer exactly what C's do, which is how a binding
  checks itself against a header; `offsetof` on a class counts from the
  allocation, so the number is what to add to the reference you hold
- Integer literals that fit convert implicitly, as in C#, and one that fits
  nothing is refused rather than truncated. A literal is the narrowest of
  `int`, `uint`, `long` and `ulong` that holds it, so a mask written the way a
  C header writes it means what it says. A floating-point literal is a `double`
  unless it carries the `f` suffix
- Shared libraries: `--shared` with a generated C header, and an export table
  containing exactly the `export "C"` functions
- **`[Embed]`**: `[Embed("logo.png")] static readonly byte[] Logo;` carries a
  file in the binary as an immortal array the linker places — no copy, no
  startup code, and legal in a `--shared` library. It goes on a module-level
  static or a type's static field and nowhere else. The path is relative to the
  source file that wrote it; `Access` makes it writable or executable and
  `Section` names where it goes, with each combination an assembler would get
  wrong refused where it is written. Run on x64 and x86, on Windows and Linux,
  and assembled for ARM64 on both. A dependency is rebuilt when a file it embeds
  changes. See [§8.7](spec/08-interop-libraries.md#87-embedding-a-file)
- **Named attribute arguments**: an attribute's fields are filled positionally
  in declaration order and then by name, `[Column("id", Width = 8)]`, with a
  field given neither way keeping its type's default. Positional first
  (SL0726), each field once (SL0725), and an unknown name refused (SL0724). An
  attribute written where nothing reads one back — a function, a `const`, an
  alias, an `extern` declaration — is an error (SL0728) rather than a dropped
  line. See [§6.1](spec/06-attributes-reflection.md#61-attributes)
- Stainless libraries consumed by Stainless: `--metadata` writes a `.slmod`
  describing a library's public surface, and `--reference` binds another
  compilation against it. Classes cross with their fields, properties, methods,
  constructors, destructors and events; so do structs, enums, free functions,
  closures and delegates, and reference counting reaches across, because an
  object is allocated through the library's own TypeInfo. Generics and classes
  implementing interfaces do not cross, and the compiler says so where the
  library is built
- **Deriving from a class in another binary.** Its layout, its dispatch table
  slot by slot, its destroy hook and its protected members all cross, so a
  derived class puts its fields after fields it never saw laid out, builds its
  table on top of one compiled elsewhere, overrides into it, and hands the
  object back to the library when its own destructor is done. What it costs is
  that the base's table length is part of its contract: adding a virtual method
  to a public class is a breaking change, and the ABI digest is what enforces
  it rather than convention
- Projects and packages: a `stainless.json` that states what a program is made
  of — a document rather than a script, so a tool can read it — plus versioned
  dependencies from a path or from git, a committed `stainless.lock`, and an ABI
  digest over every layout and signature, so a library whose surface moved under
  a fixed version is a message instead of a program reading the wrong four
  bytes. A dependency is compiled in by default, which is the model the language
  already has; `"link": "shared"` is the opt-in for a binary boundary. See
  [docs/packages.md](packages.md)
- Attributes and opt-in reflection: field names, offsets, kinds and attribute
  values readable at run time, from `const` tables in the binary
- `-g`: debug information, and `--debug-format dwarf|codeview|both` says in
  whose format. The default follows the **target** -- CodeView for Windows,
  DWARF for everything else -- so a Linux binary cross-compiled from Windows
  gets DWARF. Every instruction carries a source location, every function is
  named as it was written and as the linker sees it, and every local and
  parameter is described with its type and its stack slot. Definitions carry
  `"frame-pointer"="all"`, without which LLVM omits the frame pointer at every
  level and no debugger can walk a stack. The standard library is written to
  `obj/stdlib/` and the runtime's C compiled `-O0 -g`, so a stack trace through
  `List.Add` and into `sl_retain` names real files and real lines rather than
  addresses. See [§7 of the ABI notes](abi.md)
- [bindings/win32](../bindings/win32): the Windows API — entry points, constants,
  structs, unions, enums, delegates, handle types and COM interfaces — as
  declarations rather than a marshalling layer, in two layers a module name
  apart:
  `Win32.User32` is what the DLL exports, `Win32.Ui` is the conveniences on top.
  Source a program compiles rather than part of the standard library, because
  compiling a wrapper is what makes its library necessary; the raw layer needs
  no library at all. It reaches as far as XInput, XAudio2, DXGI and Direct3D 11,
  read out of the SDK headers' `*Vtbl` structs rather than transcribed, with
  `Win32.Gamepad`, `Win32.Sound`, `Windows.DirectX` and `Windows.DirectX11` on
  top; [samples/directx](../samples/directx) draws a lit, shadowed cube to a
  module player. Direct3D 12 is not bound
- [bindings/linux](../bindings/linux): the Linux socket calls, the terminal
  (`termios` and `ioctl`, with raw mode, the window size, the cursor and
  colour) and the event loop (`epoll`, `eventfd`, `timerfd`, `inotify`) — where
  everything is a file descriptor, so one wait covers sockets, timers, file
  changes and other threads together. On the same terms as the Win32 ones.
  `#if LINUX` and not `#if UNIX`, because the functions are POSIX and the
  numbers are not — `AF_INET6` is 10 here, 23 on Windows and 30 on macOS — so
  a file claiming to be POSIX would have to be wrong on two platforms out of
  three. Both bindings are checked against the real headers by a C file
  compiled beside the test, which is how a constant in a binding stops being
  somebody's recollection
- Conditional compilation: `#if`, `#elif`, `#else`, `#endif`, `#define`,
  `#undef`, `#error`, `#warning`, `#region` and `#endregion`, with C#'s
  condition grammar, plus `#pragma comment(lib, "...")` so a file can name the
  library it needs. A branch that is not taken is never lexed, so it need not
  parse. `WINDOWS`, `LINUX`, `MACOS`, `FREEBSD`, `UNIX`, `X64`, `ARM64`, `X86`,
  `ARM` and `STAINLESS` describe the target — the architecture one follows
  `--target`, so a binding guarded by `#if X86` compiles the half it means to;
  `-D` adds the rest. No macros and no `#include`: a name always means itself
- **Tuples**: `(int, String)`, structural, with `Item1` upwards for fields and
  `var (low, high) = MinMax(xs);` where the names matter. A tuple is a struct,
  so layout, both ABI classifiers and reference counting apply to it with
  nothing written for tuples
- **A type may be declared inside another**, and is lifted out and named for
  where it was written: `Rect.Point` from outside, `Point` from within `Rect`.
  Nesting is about where a name is reached from and nothing else — no hidden
  reference to an outer instance, and no bearing on layout. It composes, and a
  nested type does not see its outer type's parameters
- `?.`, `??` and `??=`, over a `C?`. The receiver is read once, so
  `Next()?.Name` calls `Next` one time. A reference member answers null; a
  value member has no null to answer with, so `node?.Weight` needs a
  `?? fallback` and says so (SL0605) rather than inventing a zero a caller
  cannot tell from a real one. A receiver that cannot be nothing is refused,
  and `a?.b.c` is an error where `a?.b?.c` is the question actually being asked
- `default(T)` is the zeroed value of a type, for generic code that cannot
  write a literal for a type it does not know. Not a new hole in the null
  discipline: a fresh array is zeroed, so `new C[1][0]` was the spelling before
  it. `String.Empty` is a static property rather than a field, because a
  `--shared` library has no entry point to initialize a static from
- Diagnostics with source excerpts and caret runs

## What does not exist yet

Being straight about the edges, roughly in the order they are worth adding:

- **Constraints are checked at the instantiation, not the declaration.**
  `where T : IShape` is verified where the generic is used, but the body is
  still checked per instantiation, so an unused template is never checked and
  a mistake inside one is reported against its use. Definition-site checking
  would need constraints on operators too, which is a larger step.
- **Type arguments cannot be written at a call.** `Pick<int>(...)` is rejected,
  because `<` in expression position is ambiguous with less-than, so a type
  parameter that appears only in the function's own return type cannot be
  worked out. That holds for generic methods too, and an interface method
  cannot be generic at all, since dispatch gives it one slot. A parameter that
  appears only in a *lambda's* result is a different case and is inferred, by
  binding the body once the other arguments have given it its parameter types —
  which is what makes `Select(numbers, n => n * 2)` work. The same ambiguity is
  why an instantiation cannot be *named* in expression position either:
  `new Box<int>(...)` reads, because a type is what is expected after `new`,
  but `Box<int>.Of(2)` and `Box<int>.Count` do not. A generic type's static
  members are reachable from inside it and from a value of it, and a maker for
  one is written as a module-level generic function. Inside the type its own
  statics are named directly, as they are anywhere else.
- **No `goto case`, and no exhaustiveness requirement on an enum**, whose value
  need not be one of its members. A switch expression over one still needs a
  `_` arm for that reason.
- **A lambda with nothing written needs something to be.** One that writes its
  parameter types out has a type of its own -- `var f = (int x) => x * 2;` is a
  closure -- but `var f = x => x;` has nothing to infer from and is refused
  (SL0553), and so is a block body, whose result is decided by the type it is
  becoming. Capture
  is by value only, and a capturing lambda cannot become a `delegate` — a
  function pointer has nowhere to keep what was captured. A lambda that captures `this` keeps its object
  alive, so an object holding its own closure is a cycle; `weak` is how that is
  broken.
- **No zero-width or unnamed bit-fields.** C's `int : 0;` closes a storage unit
  and `int : 3;` pads without naming anything; neither is written (SL0473).
  `[Packed]` together with bit-fields is refused rather than guessed (SL0470),
  because gcc packs the bits and MSVC keeps the unit and nothing here yet says
  which this language means. `[Reflect]` is refused on a type with bit-fields
  (SL0475): the field tables describe a byte offset, and a bit-field has none.
- **`[Align(N)]` stops at 16.** `malloc` guarantees `max_align_t` and nothing
  more, so a class holding a more-aligned field would be handed memory that did
  not honour it. Lifting the cap means allocating by a type's alignment as well
  as by its size, which the runtime does not do yet. There is also no alignment
  on a single field, only on a whole type.
- **A slice is owning, and there is no borrowed one.** It retains the array it
  came from, which is what makes it impossible to dangle and also what makes it
  cost a reference count per copy and keep a large array alive for a small view
  of it. A raw `(pointer, length)` view would do neither, and would need a
  lifetime story the language does not have.
- **Case mapping is ASCII only.** `ToUpperAscii` and `ToLowerAscii` map A–Z
  and leave every other byte alone, and say so in their names. Full Unicode
  case mapping is a table of several thousand entries with locale exceptions,
  and the runtime has no room for it yet. There is also no collation: strings
  order by their bytes, which happens to order by code point and does not
  resemble any language's idea of alphabetical.
- **`String` positions are byte offsets.** That is what makes length O(1), and
  every position the library produces lands on a character boundary because it
  came from matching whole text. A position a caller invents is its own
  business: `Substring(1, 1)` on a multi-byte character will slice it in half.
  `GetCodePointAt` and `SkipCodePoint` are the way to walk the text properly.
- **Flow narrowing does not reach a field.** `if (x != null)` makes `x` usable
  as a `C` (§2.5), on the same terms a variant is narrowed — but only for a
  local or a parameter, because a field or a call result may be a different
  value by the time it is read. `if (node.Next != null) { node.Next.Value }` is
  refused, and a local is both the fix and what the code meant. `is` with a
  name is the other fix and reads better: `if (node.Payload is Circle c)` for a
  variant's case, `if (node.Next is Node n)` for a `C?` — the value is taken
  once, so there is nothing to prove about a second read.
- **There is no covariant return.** An override returns exactly what it
  overrides (SL0502).
- **Hiding an inherited member is refused, not warned about.** C# has `new` for
  it; a language with no way to reach the hidden member has nothing to say it
  about, so the same name and parameters means `override` or nothing (SL0503).
- **Reflection describes fields, properties and array elements.** A property
  is its accessors rather than an offset, so setting one through reflection
  runs the setter — which is what anything whose setter does work needs, and
  what writing an automatic property's storage silently skips.
  `Field.IsPropertyStorage` is how the two are told apart. `FindType` looks
  a `[Reflect]` type up by its qualified name, so a document can say which type
  it wants where `typeof` cannot. **Methods and interfaces carry no metadata.**
  That is what stops a serializer filling a `List<T>`: its storage is private
  and the way in is `Add`, which nothing here can call. An array is described
  and does round-trip.
- **An interface method may not be overloaded.** Dispatch gives each one a
  single slot, so two of a name in one interface would be a call the receiver
  could not resolve. Methods on classes and structs overload freely, and a
  class may implement two interfaces whose methods share a name.
- **A property still evaluates its receiver twice under `+=`.** `p.X += 1`
  needs a receiver that is a plain load, since the getter and the setter each
  evaluate it. An indexer has no automatic form either: `{ get; set; }` would
  have nothing to find storage for.
- **The compiler prunes no dead code; the linker does.** Every stdlib module is
  compiled with your program whether or not it is imported, and only generics
  are free — an uninstantiated template emits nothing, but a non-generic
  function or class is emitted either way. What saves the binary is that
  everything goes into its own section and the linker discards what nothing
  reached: hello-world calls `puts` and returns, so it reaches *no* standard
  library function at all, and the linker throws every one of them away.

  The compile is what nothing saves. The IR is the full size however little of
  it is used, so every build pays to emit and optimise the whole library, and
  each thing added to the library is added to every program that never mentions
  it. A reachability pass from `Main` is the real answer, and the fact that the
  stripped binary comes out identical however much the library grows is the
  measure of how completely the compiler is leaving the job to the linker.
- **Unoptimized ARC.** Retain/release traffic is correct but redundant, and a
  redundant pair costs more since the counts became atomic. The +0/+1 dataflow
  pass that removes the pair around a borrow is the fix.

  Worth knowing how much is actually at stake, because the obvious measurement
  overstates it. Counting `sl_retain` and `sl_release` in a module is not
  counting what runs: nearly all of them are in library functions the program
  never calls, so that number is really about the missing reachability pass
  above. **A read through a reference already borrows** — `cells[i].Value` in a
  loop emits no reference counting at all — so what is left to remove is
  narrower than it looks. The runtime declarations now tell LLVM what is true
  of each entry point (`sl_retain` touches only the object's header;
  `sl_release` may run any destructor and so promises nothing; the failure
  paths do not return), which is worth having for its own sake and measurably
  changes nothing. Only the +0/+1 pass will.
- **Thread safety is advice, not a proof.** What crosses a thread is checked
  by type and warned about, and `threadsafe` is an assertion -- the same bargain
  as Rust's `unsafe impl Sync`. What is unchecked entirely is how long a
  borrowed thing lives: a `Guard` can outlive the lock it proves, and a job
  could store an array it was only lent. See
  [docs/concurrency.md](concurrency.md).
- **No cancellation beyond a shared flag.** An `AtomicBool` a job polls is the
  whole story; a `parallel` block always joins, and always will. See §9 of the
  concurrency notes for what is worth adding and what never will be.
- **Debug information describes data, not sequences.** `-g` covers functions,
  locations, locals, parameters, structs, class bodies and enums, each local in
  the block it was declared in, and an array's or a `String`'s elements as a
  member claiming no bound — DWARF wants a static bound and the real one is the
  length beside them, so what is described is the element type and its stride.

  One is worth knowing before reading any of it back: `DW_AT_language` is
  `DW_LANG_C_plus_plus`, which will mislead any consumer that demangles by
  language. A DWARF build on Windows also describes the Stainless module
  alone, because the C runtime's objects are compiled for the MSVC target and
  carry CodeView.
- **A variant does not cross a library boundary or carry `[Reflect]`.** Both
  are reported where they are written (SL0441, SL0442) rather than left to be
  discovered. The metadata describes layouts and the reflection tables describe
  fields, and a variant's shape is neither — it is its cases, which nothing yet
  writes down. Its tag is also one byte, so 255 cases is the limit.
- **A `--shared` library cannot have a static**, of a module or of a type,
  unless its value is a literal — a number, `null`, `default` — or an
  `[Embed]`, that the global can simply be born holding: there is no entry
  point to run any
  other
  initializer from (SL0380). There is no
  per-thread storage either, and no automatic static property -- its backing
  storage would have no initializer, which is the one moment a static has.
- **An enum does not become its number at `extern "C"`.** It crosses as exactly
  its underlying integer where the declaration names the enum, but a
  `[Flags] enum : uint` will not pass to a `uint` parameter without a cast, which
  is why
  [bindings/win32](../bindings/win32) spells its constants as bare `const uint`
  rather than as the typed sets they are.
- **An inline array holds plain data only** and cannot be passed by value
  (SL0486, SL0491). The first is the same question a union cannot answer; the
  second is because C decays an array parameter to a pointer and Stainless has
  no decay, so `ref T[N]` is the spelling that lines up.
- **Sockets are blocking, and there is no TLS.** `Standard.Net` has one
  socket's worth of waiting — `WaitToRead`, `WaitToWrite` and a non-blocking
  mode — and nothing that waits on many at once, so a server that holds a
  thousand connections wants a thread each. There is no `select` or `epoll`
  over a set, no async, and nothing encrypted: a program that needs TLS reaches
  for the platform's own through `extern "C"`. `Socket.Connect` on a socket
  that is already open tries one address rather than all of them, because a
  socket whose connect failed cannot be reused and that one is already made —
  `Socket.OpenConnected(host, port, ...)` is the form that tries each.
- **No portable COM *client* activation.** Being a server is done everywhere:
  a class factory, a table of them and `DllGetClassObject` all work on any
  platform, because none of that is Windows. What is missing is the other
  direction — a `Com.CreateInstance(clsid, ...)` that finds a module, loads it and asks
  it, so a caller need not know where the class came from. On Windows
  `Win32.Com` and `Win32.ShellCom` bind the real thing, so `CoCreateInstance`,
  `IShellItem` and `IFileDialog` all work today. Absent everywhere are the
  parts nobody has asked for: apartments beyond `CoInitializeEx`, marshalling,
  proxies and stubs, `IDispatch`, and aggregation, which `CreateInstance`
  refuses outright.
- **A library's surface is narrower than a module's.** `--metadata` lets a
  Stainless library be consumed by Stainless, but a generic, a class that
  implements an interface and a variant all stay behind: a template emits
  nothing until it is instantiated, a dispatch table is indexed by an id
  assigned across a whole program, and a variant's cases are not a layout. A
  slice or a tuple of what the metadata describes does cross.
  Anything reaching one of those through a field or a signature is reported too
  (SL0419, SL0420, SL0441, SL0477), all of them where the library is built
  rather than where the consumer trips over them.
- **The shared runtime is a file to carry.** Where two Stainless binaries meet
  the runtime is one shared library, which is what puts them on one allocator
  and one stdio buffer — and it then has to sit beside them. The compiler copies
  it there, but a binary moved on its own will not find it. A program with no
  library boundary keeps the copy compiled in and stays standalone, which is
  what the default is about.
- **No `ref` locals and no `ref` returns**, which would need a lifetime story
  the language does not have. `out` does exist, and brought the language's only
  definite-assignment analysis with it: every path out of the function has to
  write the parameter (SL0600), and the caller's storage is cleared before the
  call so that a hole in that produces a zero rather than whatever the stack
  held. An ordinary local read before it is written is still nobody's business
  but the author's.

---

<sub>[&larr; README](../README.md) &nbsp;&middot;&nbsp;
[TODO.md &rarr;](../TODO.md)</sub>
