<sub>[Stainless](../../README.md) &rsaquo; Design notes</sub>

# Zero values

A design, not yet the language. It settles how the rule below is to be
enforced and what replaces each thing it takes away. A prototype of the check
is in the compiler, off by default; §9 says how to run it.

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

Two things this table needs that the language lacks:

- **`T[]?`.** Today `byte[]?` is SL0271, so a struct or class field holding an
  array that is sometimes absent has no honest type. `T[]?` has to exist before
  the rule is on, with the same representation as `T[]` and the same narrowing
  as `C?`. `Span<T>`'s own `_array` field becomes `T[]?`, which is what makes
  the empty span a value rather than an exemption.
- **`closure?`.** A closure field that starts empty (`SearchBox._onSearch` in
  the GTK sample) has no type today. `Notify?` is a closure whose function word
  may be null, asked by `?.`/`!= null` like any other optional. Its
  representation is the closure's own two words.

A variant whose tag 0 case holds a reference is the one that surprises:
`Result<T, E>` declares `Ok` first. It has no zero value, and it does not need
one — nothing builds a `Result` other than by naming a case.

## 4. Definite assignment

The language has one definite-assignment analysis today, for `out` parameters
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

**A. An uninitialised-array primitive** (recommended).

```csharp
// Standard.Unchecked — the whole surface
public T[] NewUninitializedArray<T>(nuint length);   // every slot zero bytes, not yet a T
public void ClearElement<T>(T[] array, nuint index);  // release, then zero bytes again
```

The array is an ordinary `T[]` whose slots may hold zero bytes that are not a
`T`. The invariant is the library's: **a slot is written before it is read, and
cleared when it is vacated.** It is what `new T[n]` and `default(T)` already
compile to — the same allocation and the same store — so it costs nothing
per element and changes no layout. ARC is already safe with it: releasing a
zero slot is a no-op, which the runtime relies on today.

It is unsound in the way Rust's `MaybeUninit` and `Vec`'s raw buffer are: a
contained, named obligation on a few hundred lines of library, instead of an
invisible one on every program. The names say what they are, the module says it
again, and a program that imports `Standard.Unchecked` has written that it is
taking the obligation on. Migration is mechanical: `new T[n]` → 
`NewUninitializedArray<T>(n)` and `a[i] = default(T)` → `ClearElement(a, i)`,
about 46 and 30 sites in the collections, with no change to any algorithm.

**B. Storage of an optional wrapper** — `Optional<T>[]`, or a `Slot<T>` variant.
Sound by construction. Rejected: the tag is per element, so `List<int>` goes from
4 bytes a slot to 8 and `List<long>` from 8 to 16, and every read pays a tag
test. There is no free `T?` for a generic `T`: `C?` is free because a reference
has a spare bit pattern, and `int` has none.

**C. A runtime buffer that knows its live prefix** — a counted object with a
capacity and a count, bounds-checked against the count, released only up to
it. Sound and free, and a good fit for `List`, `Stack` and `ArrayBuilder`.
Rejected as the primitive because the rest do not keep a prefix: a hash table's
live slots are scattered and a ring buffer's wrap. It would need B or A beside it
for those, so it adds a mechanism without removing one. It remains a sensible
later refinement of `List<T>` on top of A.

A also covers the compiler's own growable buffer behind collection expressions
with spreads, and event storage, which the compiler already fills slot by slot.

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
`Array.Create`/`Array.Repeat` and the `Standard.Unchecked` pair.

The order that keeps the tree building: the new types and constraints first,
then `Standard.Unchecked` and the collections, then the diagnostics as warnings,
then the call sites tree by tree, then warnings become errors.

## 9. Diagnostics

Provisional numbers, written here without their `SL` so that the unit tests,
which hold every documented code to a pinning case, do not yet count them.
The prototype reports the first five as `SL` and the number. Each MUST be
pinned by an `errors.txt` case, and written with its `SL`, when it is turned on.

| Code | Says |
|---|---|
| 0810 | `default` for a type with no zero value, naming the slot: *'Holder' has no zero value: 'Holder.Data' is a 'byte[]', which is never null* |
| 0811 | a local read, or passed by `ref`, before every field is assigned |
| 0812 | `new T[n]` for such an element, pointing at `Array.Create`, a literal and `List` |
| 0813 | a constructor that can finish without writing such a field, at the path that does; or a field no constructor could write |
| 0814 | a static property of such a type with no value |
| 0815 | an argument that fails `zeroable`, as SL0328 reports the others |
| 0816 | a member whose own `where` its type's arguments fail, named at the call |

Inside an instantiation each names the instantiation, as a constraint failure
does.

**The prototype.** `STAINLESS_ZERO_VALUES=warn` or `error` reports 0810–0814
as the table has them; `log` reports nothing. `STAINLESS_ZERO_VALUES_LOG=path`
appends one tab-separated line per finding, and one per template site whose
type names a type parameter whatever it was instantiated with. It does not yet
follow private helpers (§4.2), does not track fields of a local separately
(§4.1; it records what first touches the local), and has neither `zeroable` nor
member constraints. Off, it costs one test per site.

## 10. Interactions

- **C interop.** Unaffected: a type with a counted reference cannot cross to C
  already, and pointers and delegates have zero values.
- **A library boundary.** Whether a type has a zero value follows from its
  fields' types, which the metadata carries for layout, so a consumer decides it
  without the source. A library's templates are instantiated by the consumer,
  who is told at the instantiation.
- **Reflection.** `CreateInstance` and `CreateArrayInto` make zeroed objects
  and arrays through `byte*`, and their documentation already says the result is
  not a value of its type until filled. They stay as they are: they are pointer
  APIs, whose obligations are the caller's, and `Json.PopulateObject` fills in
  place instead. A deserializer target that `Json` makes from nothing wants its
  never-null fields `required`, which `Json` MUST then fill or fail.
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
