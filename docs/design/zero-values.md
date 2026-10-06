<sub>[Stainless](../../README.md) &rsaquo; Design notes</sub>

# Zero values

The rationale behind [§2.16 of the specification](../spec/02-types.md#216-zero-values),
which is the rule as the language has it. This note is what was weighed on
the way there: the survey, the alternatives rejected, and where the
implementation departed from the design (§12).

---

## 1. The hole

`String`, `byte[]` and a class `C` are never null ([§2.5](../spec/02-types.md#25-pointers-and-nullability)),
and every read of one trusts that. But a zero value puts a null in exactly such
a slot, and nothing asks:

```csharp
public struct Holder { public byte[] Data; }

Holder held = default;
Console.WriteLine($"{held.Data.Length}");     // a read at address zero
```

Every route to a zero value does it: `default(S)` and a bare `default`, a local
declared without a value, `new S[n]`, `new String[n]`, `new C[n]`, a field its
constructor never wrote, and each of these in generic code for a `T` that turns
out to be one of them. The tree has real instances, not only contrived ones:
`ECCurve.CreateFromFriendlyName` answers an unknown name with `ECCurve none;
return none;`, whose `_oid` is a `String` that is null.

## 2. The rule

**A type whose zero value would hold a null in a non-nullable reference has no
zero value.** Making one is a compile-time error. Such a value is built by a
constructor or an initializer, and an array of them by something that supplies
every element. This is Rust's and Swift's rule; C# 8 made the same promise with
warnings and kept `default` as the hole.

A nullable form (`C?`, `String?`, `T[]?`) and a type with no reference in it
keep their zero values, so `int x;`, `new double[n]` and `default(Node?)` are
unchanged. So is every `unmanaged` type: nothing the rule refuses crosses to C.

## 3. Which types have a zero value

Decided by `ZeroValues.FindNullInZero`, which also names the slot that fails,
so the diagnostic can say *which* field is the problem:

| Type | Zero value | Why |
|---|---|---|
| primitive, enum, pointer, `delegate` | yes | a delegate's zero is its `null` (§2.14) |
| `C?`, `String?`, `I?`, `weak C?` | yes | null is a value of the type |
| class, interface, COM interface, `String`, `T[]` | **no** | never null |
| `closure` | **no** | its function word is null, and a call does not ask |
| struct, tuple, record struct | if every field has one | transitive |
| `T[N]` inline array | if its element has one | always true today: SL0486 keeps references out |
| `union` | yes | a union may not hold a counted reference |
| `variant` | if the case with tag 0 has one | a zero tag is the first case, its payload zeroed: `Optional<String>`'s zero is `None`, `Result<String, E>`'s is `Ok(null)` |
| `Span<T>`, `ReadOnlySpan<T>` | yes | the empty span; its length is zero so its array word is never read |

Two things this table needs that the language lacked, both built with the rule:

- **`T[]?`.** Without it `byte[]?` was SL0271, so a struct or class field
  holding an array that is sometimes absent had no honest type. `T[]?` has the
  same representation as `T[]` and the same narrowing as `C?`. `Span<T>`'s own
  `_array` field is `T[]?`, which is what makes the empty span a value rather
  than an exemption.
- **`closure?`.** A closure field that starts empty (`SearchBox._onSearch` in
  the GTK sample) needs one. `Notify?` is a closure whose function word may be
  null, asked by `?.`/`!= null` like any other optional. Its representation is
  the closure's own two words.

A variant whose tag 0 case holds a reference is the one that surprises:
`Result<T, E>` declares `Ok` first. It has no zero value, and it does not need
one — nothing builds a `Result` other than by naming a case.

## 4. Definite assignment

The language had one definite-assignment analysis, for `out` parameters
(SL0600, `Binder.Assigns`). The prototype generalises it from "this parameter"
to any `AssignedPlace`, and the rule runs every question below through that one
walk, with its existing stand-down for `goto`.

### 4.1 Locals

`S x;` is allowed, and **every field of `x` must be definitely assigned before
`x` is read**, which is C#'s rule for struct locals. Assigning the whole of it
assigns every field; writing `x.F` assigns `F`. A read of `x`, a `ref x`, or a
read of a field not yet written is the error.

Requiring an initializer instead was rejected: 27 sites build a struct field
by field and then return it (`EndPoint.Create`, `VertexField.FromSemantic`,
`PaintEventArgs.FromGraphics`), which is the idiom for a struct with no
constructor, and forbidding it would force a constructor onto every one of them
for no safety gained. `out x` counts as a whole write, as it does now.

The zeroing of a local stays. It is what the emitter and ARC rely on — a
release of a slot that was never written must find null — and it costs nothing
the rule changes. What changes is that nothing can *read* the zero.

### 4.2 Fields of a class or struct

**Every constructor writes every field whose type has no zero value, on every
path through it**, unless one of these already does:

- a field initializer (it runs at the head of every constructor that does not
  delegate);
- `: this(...)`, which hands the whole obligation to the constructor it calls;
- `required` on the field or its property, which moves the obligation to every
  `new`, where §7.3.2 already enforces it — and `[SetsRequiredMembers]` on a
  constructor moves it back, so that constructor is checked as though the
  field were not required;
- the primary constructor, for the fields it keeps.

A `return` before the write, and a `try` that can return before it, are the same
errors they are for `out`. A class with no constructor at all has only its
initializers, so a field with neither is an error at the declaration. An
event's storage is the compiler's and is exempt; so is a lambda's environment.

**The walk follows a call on `this` to a private method of the same type**, as
though its body were written at the call. This is the one place it looks
through a call, and it is here because of how forms are built: the designer's
generated half is `InitializeComponent()`, and `ButtonsForm`, `Shell` and every
Forms sample assign their controls in helpers of that kind — 21 of the 37
constructor findings. A private method cannot be overridden and has one body,
so following it is exact; the walk memoises what each method writes and stands
down on recursion. A non-private method is not followed: an override could
write nothing.

C#'s alternatives were considered. `[MemberNotNull]` on the helper is an
annotation the author must keep in step with the body, and the compiler would
have to check it anyway; following the call checks the same thing with
nothing to write. Kotlin's `lateinit` and Dart's `late` make the field
nullable in all but name and move the crash to the first read; that is the hole
this design closes, spelled.

**The one gap left open is `this` escaping a constructor.** A constructor that
hands `this` to something, or calls a virtual method, before every field is
written can have that field read as null. Swift closes it with two-phase
initialisation, forbidding any use of `self` until every field is set; that
would refuse `base(WindowBorder.Sizable)` followed by `Text = ...` in every form
in the tree, because the base constructor dispatches. C#, Java and Kotlin leave
the gap, and so does this. It is narrower than today's by the whole of §1.

### 4.3 Statics

A static already needs a value (SL0376). The one zero left is an automatic
static property with no `= value`; for a type with no zero value it needs one,
or a static constructor that assigns it on every path.

### 4.4 `out` parameters

Unchanged. The callee is already held to writing one, and the caller's storage
is cleared before the call; for a type with no zero value that clearing is
never observed, because the callee's write is certain.

## 5. Arrays

`new T[n]` for a `T` with no zero value is an error. What replaces it, by what
the site is doing:

| The site | Replacement |
|---|---|
| a fixed set of elements | an array literal, `[a, b, c]` — unchanged, already exact |
| `n` elements, each computed | **`Array.Create<T>(nuint count, Func<nuint, T> make)`**: allocates `count` and calls `make(i)` in order, so no slot is ever observed empty. Monomorphized, `make` is a direct call and the loop is the loop the site had |
| `n` copies of one value | `Array.Repeat<T>(T value, nuint count)` |
| an unknown number, collected | `List<T>`, then `ToArray()` — or a collection expression with spreads, which already does this |
| an empty array | `[]`, or `new T[0]`, which has no elements to be zero and stays legal for every `T` |

`Array.Create` is a fill form rather than new syntax (`new T[n](i => ...)`,
say) because a library function is enough and a second meaning for `new` is
not. It is the site's own loop moved into a lambda, and 45 of the 59 concrete
sites are `new String[n]` followed by exactly that loop (`String.Split`,
`Env.GetArguments`, the clipboard readers).

A partially filled array is impossible from these by construction. The library
has the one primitive that can make one (§7), and it is not for this.

## 6. Generics

**Checked per instantiation**, as everything in a template already is
([§4.3](../spec/04-generics.md#43-what-a-constraint-does-and-does-not-do)).
`default(T)` in `Box<T>` is fine for `Box<int>` and an error for `Box<String>`,
reported at the site in the template with the instantiation named, as
constraint failures inside instantiations are today. Monomorphization means the
binder sees each `T` as the concrete type, which is what the prototype checks.

Per-instantiation checking alone has one sharp edge: **every member of an
instantiated type is bound, whether it is called or not.** The survey shows
it — `Span<TimeZoneInfo>.Clear()` is reported although nothing calls it, only
because a `Span<TimeZoneInfo>` exists. So two additions go with the rule:

- **A `zeroable` constraint**, contextual like `unmanaged`: `where T :
  zeroable` demands a type with a zero value, is checked at the instantiation
  like any other, and lets a template say in its signature what it needs.
  `unmanaged` implies it. (`default` would read better and is taken: it is the
  override constraint, §4.3.)
- **A `where` on a member of a generic type, constraining the type's own
  parameters.** `public void Clear() where T : zeroable` on `Span<T>` means
  `Span<String>` has no `Clear`: the member is not instantiated for arguments
  that fail it, and naming it is an error at the call, where C# and Rust report
  it (Rust's `impl<T: Default>`, Swift's conditional extension). Without this,
  `Span<String>` itself would be an error.

Rejected: requiring `zeroable` for any `default(T)` at the definition. It is
definition-site checking, which §4.3 declines for good reasons, and it would
force a constraint onto `List<T>` that the collections' escape hatch (§7) makes
unnecessary.

Rejected: an implicit instantiation-time exemption for unused members only.
Binding members lazily is a larger change to pass 11 than a constraint, and it
would make whether `Span<String>` compiles depend on which methods a program
happens to call.

## 7. The collections' escape hatch

`List<T>`, `Dictionary<TKey, TValue>`, `HashSet<T>`, `Queue<T>`, `Stack<T>`,
`SortedList`, `LinkedList`'s node pool, `ArrayBuilder<T>`, the sort scratch
buffers and the concurrent collections built on them all keep storage whose
unused slots are not values yet, and blank a vacated slot with `default(T)` so
it releases what it held. None of them may cost `List<int>` anything per
element. Three mechanisms were compared.

**A. An uninitialised-array primitive.**

```csharp
// the whole surface
public T[] NewUninitializedArray<T>(nuint length);   // every slot zero bytes, not yet a T
public void ClearElement<T>(T[] array, nuint index);  // release, then zero bytes again
```

An ordinary `T[]` whose slots may hold zero bytes that are not a `T`, with the
obligation -- write before read, clear when vacated -- on the library that
imports it. It costs nothing and changes no layout. Rejected, because it is
unsound in the way Rust's `MaybeUninit` is: reading a slot never written hands
out a null where the type says there is none, and the rule that exists to stop
exactly that does not reach inside the module that holds the exemption.

**B. Storage of an optional wrapper** (taken) -- `Slot<T>`, compiler-known.
Sound by construction: its zero is empty, and a read of an empty slot of a
`T` with no zero value stops the program. And it costs nothing:

- when `T` has a zero value a slot is laid out as `T`, empty is that zero, and
  a read is one load, so `List<int>` is four bytes a slot as it always was;
- when `T` has none it holds a never-null reference, whose null is spare, so
  `Optional<T>` needs no tag (a niche, as Rust lays out `Option<&T>`) and a
  slot of it is the size of `T`. A read is one comparison with null more than
  a plain load.

There is still no free `T?` for a generic `T`; what makes this free is that
the only `T` that needs a representation of "not there" is one that already
has a spare bit pattern. `Array.Create` fills a `T[]` in place where it is
called, which is how an array of such a `T` is made without a slot.

**C. A runtime buffer that knows its live prefix** — a counted object with a
capacity and a count, bounds-checked against the count, released only up to
it. Sound and free, and a good fit for `List`, `Stack` and `ArrayBuilder`.
Rejected as the primitive because the rest do not keep a prefix: a hash table's
live slots are scattered and a ring buffer's wrap. It would need B or A beside it
for those, so it adds a mechanism without removing one. It remains a sensible
later refinement of `List<T>` on top of B.

B also covers the compiler's own growable buffer behind collection expressions
with spreads; event storage the compiler fills slot by slot, as it does an
array literal.

## 8. Migration

Every finding in the tree, from the prototype run over the whole standard
library, every sample, `forms/`, `ide/`, `debug/`, the GTK bindings and all 566
end-to-end cases. A site reached through several instantiations is counted
once; `generic` means the site is in a template and failed for at least one
instantiation the tree makes.

| Category | stdlib | forms | ide | debug | samples | bindings | tests | total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `default` in generic code | 11 | | | | | | 1 | 12 |
| constructor leaves a field unwritten | 4 | 17 | 2 | | 3 | | 11 | 37 |
| class with no constructor | | | | | 1 | | 9 | 10 |
| local, built field by field (legal under §4.1) | 5 | 2 | 2 | | 2 | 3 | 13 | 27 |
| local, whole-assigned first (legal if on every path) | 3 | | | | | | 2 | 5 |
| local, read before any write | 2 | | | | | | 3 | 5 |
| local, never used | | | | | | | 2 | 2 |
| `new T[n]`, concrete element | 6 | 13 | 3 | 2 | 2 | 5 | 28 | 59 |
| `new T[n]` in generic code | 42 | | | | 4 | | 8 | 54 |
| static property with no value | | | | | | | 1 | 1 |

By grep, which also sees templates nothing instantiates: `new T[` 46 times and
`default(T)` 37 times in the standard library, all in `Collections/`,
`Standard/ArrayBuilder.sl`, `Optional.sl`, `Span.sl`, `ReadOnlySpan.sl` and
`Time/TimeOnly.sl`; 6 and 0 in the samples; 14 and 5 plus 17 bare `default`s in
the test cases; none in `forms/`, the IDE, `debug/` or the bindings.

What each becomes:

- **The collections** (≈80 sites): §7's primitive. Mechanical.
- **`default(T)` as "not found"** — `List.Find` and `FindLast`, and `MinBy`
  and `MaxBy` on an empty sequence: an API change, to `Optional<T>` or a `Try`
  form with `out`. Four methods, and their callers.
- **`default(T)` after a call that does not return** (`Optional.GetValue` after
  `sl_fail`): a `[DoesNotReturn]` on the extern, so the tail is unreachable and
  needs no value.
- **`Span<T>.Clear`** and anything else meaningful only for a zero-able `T`: a
  member `where T : zeroable` (§6).
- **Constructor fields** (37): 21 are assigned in a private helper and pass
  once §4.2 follows the call. The rest are real: `Uri._scheme` and `_path` are
  left to `Resolve`, a private helper; `TimeZoneInfo._rule`,
  `Lazy<String>._value` and the test cases' `String` fields need an initializer,
  a `?`, or `required`.
- **Classes with no constructor** (10): `required`, an initializer, or `?`. Two
  are reflection targets that `Json` fills (`samples/json.sl`'s `Person`),
  which want `required` or `String?` — see §10.
- **Unassigned locals**: the 27 built field by field are legal; the 5 read
  first are bugs, `ECCurve none` among them, which becomes `String? _oid` or a
  named "no curve" value.
- **`new String[n]` and friends** (59 + the generic 12 outside the
  collections): `Array.Create`, a literal, or a `List`.

**The size**: about 150 sites in the standard library, 35 in `forms/`, 7 in
the IDE, 2 in `debug/`, 12 in the samples, 8 in the bindings and roughly 100
in the test cases — around 320 edits, most of them one line, plus four
signature changes in `Standard.Collections` and their callers. The
counts for constructors include the fields §4.2 accepts through a helper, and a
local is categorised by what first touches it rather than by every path. The compiler side
is `T[]?`, `closure?`, `zeroable`, member `where` clauses, the definite
assignment of §4 built on the prototype's walk, `[DoesNotReturn]`,
`Array.Create`/`Array.Repeat` and `Slot<T>`.

The order that keeps the tree building: the new types and constraints first,
then `Slot<T>` and the collections, then the diagnostics as warnings,
then the call sites tree by tree, then warnings become errors.

## 9. Diagnostics

Each is pinned by an `errors.txt` case: `err-zero-default`, `err-zero-local`,
`err-zero-array`, `err-zero-constructor`, `err-zero-static`, `err-zeroable`
and `err-member-constraint`.

| Code | Says |
|---|---|
| SL0810 | `default` for a type with no zero value, naming the slot: *'Holder' has no zero value: 'Holder.Data' is a 'byte[]', which is never null* |
| SL0811 | a local read, or passed by `ref`, before every field is assigned |
| SL0812 | `new T[n]` for such an element, pointing at `Array.Create`, a literal and `List` |
| SL0813 | a constructor that can finish without writing such a field, at the path that does; or a field no constructor could write |
| SL0814 | a static property of such a type with no value |
| SL0328 | an argument that fails `zeroable`, as it reports every unmet constraint |
| SL0816 | a member whose own `where` its type's arguments fail, named at the call |

Inside an instantiation each names the instantiation, as a constraint failure
does.

The prototype that made the survey in §8 was switched by
`STAINLESS_ZERO_VALUES`; it is gone, and the rule is always on.

## 10. Interactions

- **C interop.** Unaffected: a type with a counted reference cannot cross to C
  already, and pointers and delegates have zero values.
- **A library boundary.** Whether a type has a zero value follows from its
  fields' types, which the metadata carries for layout, so a consumer decides it
  without the source. A library's templates are instantiated by the consumer,
  who is told at the instantiation.
- **Reflection.** `CreateInstance` and `CreateArrayInto` made zeroed objects
  and arrays through `byte*`. They were changed rather than left: see §12.
  A deserializer target that `Json` makes from nothing wants its never-null
  fields set by its constructor or `required`, which `Json` MUST then fill or
  fail.
- **`[Embed]`.** A `byte[]` the linker makes, never null.
- **Events.** Their storage is an array the allocation fills and the compiler
  grows; it is exempt, and never holds an empty slot.
- **`Main(String[] args)`.** Built by `Env.GetArguments`, whose `new String[n]`
  becomes `Array.Create`.
- **Statics.** Already need a value; §4.3 covers the property that did not.
- **Weak references.** Nullable by nature, so never the problem.

## 11. Not in scope

Two neighbouring holes with the same shape and a different cause: an `enum`
with no zero member, whose zero names nothing, and a `variant` with no case at
tag 0. Neither is a null, and neither is decided here.

## 12. As implemented

The rule is on, as errors, and the tree was brought to it in the same change.
Where the implementation settled something this note left open, or departed
from it:

- **The survey, again.** Re-run on the tree after the crypto, TLS and HTTP
  work landed, with the prototype's first-touch categories, it counted 197
  sites: 78 in the standard library, 10 in `forms/`, 6 in the IDE, 2 in
  `debug/`, 16 in the samples, 8 in the bindings and 77 in the test cases.
  Once locals were tracked a field at a time and constructors followed their
  helpers, what was actually refused came to about 100, most of them test
  cases writing `new String[n]` and filling it.
- **`Notify?` is a closure type of its own**, a twin of `Notify` with the same
  two fields and the same LLVM type, rather than an optional wrapping one. An
  optional is one pointer everywhere the emitter looks; the twin is a struct
  every existing path already handles, and only the binder's narrowing,
  comparison with `null` and call checks learn about it.
- **A struct field of a class is written a field at a time**, as a local is:
  `TimeZoneInfo` writes `_rule.StandardName` and `_rule.DaylightName` in its
  constructor, and §4.2 said nothing either way.
- **An automatic property's setter writes its storage** for a struct local,
  as it does for a constructor, so `Slot s; s.Item = x;` is a whole write.
- **Storage a property reads only through `field ??=` may start empty.** The
  specification had said that a reference-typed property's storage starts null
  whatever its type says; the pattern that relies on it, filling on first use,
  never reads the null, so the parser records whether every mention of `field`
  in an accessor is what `??=` fills, and such storage is exempt from SL0813
  and SL0814. Any other read of `field` makes it an ordinary field again.
- **A member `where` on a dispatched member is SL0334**: a virtual, abstract, override or interface
  member is in every instantiation's table, so it cannot be left out.
- **`class, zeroable` is SL0581**, the contradiction every other pair of kinds
  gets: a reference that is not optional is never null.
- **`MinBy` and `MaxBy` had aborted on an empty sequence**, not answered
  `default(T)`; they now answer `None`. `Min`, `Max` and `Aggregate` keep
  aborting, and take their seed from the first element.
- **`Span.Clear` of references** was what a test used to watch releases
  happen; that test now clears a `Span<Trace?>`.
- **`ECCurve` keeps its zero value**, "no curve", by making `_oid` a `String?`
  rather than naming a "none" curve.
- **`Json` array fields that may be absent** are `T[]?`; the element columns of
  a field's metadata look through the optional, which they had not.
- **Reflection did not stay as it was.** §10 had left `CreateInstance` and
  `CreateArrayInto` making zeroed storage, as pointer APIs whose obligations
  were the caller's; that left `Json` handing out objects with nulls in their
  never-null fields, patched only for `String`. Two shapes were weighed. One
  filled each never-null field with an empty value — `""`, an empty array, a
  nested struct recursively — and refused a type with a class, interface or
  closure field it could not fill; it was rejected because it invents values
  a `required` member exists to refuse, and cannot fill the one kind of field
  a deserializer most needs to. The other, taken, makes an object only by
  running the constructor `new T()` would, through a `create` function the
  compiler puts in a reflected class's `TypeInfo`; what that constructor leaves
  — `required` members, a new array's elements — is written by a `fill`
  callback and checked, from new `SL_FIELD_NO_ZERO`, `SL_FIELD_REQUIRED` and
  `SL_FIELD_ELEMENT_NO_ZERO` bits in the field table, before anything is handed
  out. There is no longer any way to make a zeroed object. `Json` builds on it
  and fails with `MissingMember` rather than storing an incomplete object.
- **A static read through a call was not ordered.** `static String A = F();`
  with `F` reading a later static read its zero; the sort now follows calls,
  constructors, closures and delegates through every body, and a static that
  reaches itself that way is SL0378 as one naming itself is.
- **An activated com class could leave a `required` member null**, since a
  class factory writes no initializer. It is SL0611 unless the empty
  constructor is `[SetsRequiredMembers]`.
