# Standard

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

The language's own vocabulary: the markers and types that are rules rather
than library features, and so need no import to reach.

## Contents

**Types** &nbsp; [Action&lt;T&gt;](#actiont-closure) &middot; [Comparer&lt;T&gt;](#comparert-closure) &middot; [Fold&lt;A, T&gt;](#folda-t-closure) &middot; [Func&lt;T, R&gt;](#funct-r-closure) &middot; [Optional&lt;T&gt;](#optionalt-variant) &middot; [Predicate&lt;T&gt;](#predicatet-closure) &middot; [Result&lt;T, TError&gt;](#resultt-terror-variant)

## Types

### Action&lt;T&gt; *closure*

```
closure void Action<T>(T value)
```

Does something with a T and returns nothing.

**Type parameters**

- `T` — what is handed to it

<sub>[stdlib/Standard.sl:100](../../stdlib/Standard.sl#L100)</sub>

### Comparer&lt;T&gt; *closure*

```
closure int Comparer<T>(T left, T right)
```

Orders two Ts: negative if `left` comes first, positive if `right` does,
zero if neither.

This is what lets a type be sorted more than one way, and what lets a type
that implements no interface be sorted at all.

**Type parameters**

- `T` — what is being ordered

<sub>[stdlib/Standard.sl:118](../../stdlib/Standard.sl#L118)</sub>

### Fold&lt;A, T&gt; *closure*

```
closure A Fold<A, T>(A total, T value)
```

Folds one T into a running A. Two parameters rather than one, because a
fold is the one shape that carries something along with it.

**Parameters**

- `total` — what has been accumulated so far
- `value` — the next element to fold in

**Type parameters**

- `A` — what is carried along, and what the fold answers with
- `T` — what is folded over

<sub>[stdlib/Standard.sl:109](../../stdlib/Standard.sl#L109)</sub>

### Func&lt;T, R&gt; *closure*

```
closure R Func<T, R>(T value)
```

Turns a T into an R. The transform half of `Select`.

**Type parameters**

- `T` — what goes in
- `R` — what comes out

<sub>[stdlib/Standard.sl:90](../../stdlib/Standard.sl#L90)</sub>

### Optional&lt;T&gt; *variant*

```
variant Optional<T>
```

A value, or none -- for the types `T?` cannot describe.

`C?` is a nullable reference: the null is the pointer, so it costs nothing
and the compiler narrows it. A value type has no spare bit to be null with,
so `nuint?` is refused (SL0271), and what stood in was a magic number --
`IndexOf` answering with the largest `nuint` there is and every caller
agreeing to read that as "not there".

This is that, said properly. It is an ordinary variant, so it costs a tag
beside the value and nothing else: no allocation, and the payload is only
read where the compiler has established the case.

    if (map.IndexOf(key) is Some found) { return values[found.Value]; }
    return fallback;

**Not a replacement for `C?`.** A nullable reference stays what it is: the
representation is already free there, and `if (c != null)` narrows without
a case to name. This is for everything a null pointer cannot say -- which
is also why the names differ: `Optional<T>` is this type, and "an optional"
is what the spec calls `C?`.

**Type parameters**

- `T` — what it may hold -- a value type, usually, since a reference already has `C?`

<sub>[stdlib/Standard.sl:159](../../stdlib/Standard.sl#L159)</sub>

#### None *case*

```
None
```

There is no value. Carries nothing, so there is nothing to read by
mistake.

<sub>[stdlib/Standard.sl:163](../../stdlib/Standard.sl#L163)</sub>

#### Some *case*

```
Some(T Value)
```

There is one, and `Some` carries it. Reached with `is Some x`, which
takes the value and names it in the same step.

<sub>[stdlib/Standard.sl:167](../../stdlib/Standard.sl#L167)</sub>

#### HasValue *property*

```
bool HasValue { get; }
```

True when there is a value. The reader for a caller that is about to
ask a second question anyway; `is Some x` is the one that gets at it.

<sub>[stdlib/Standard.sl:171](../../stdlib/Standard.sl#L171)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is not. The same question the other way round, because
`!x.HasValue` reads worse than the thing it means.

<sub>[stdlib/Standard.sl:183](../../stdlib/Standard.sl#L183)</sub>

#### GetValue *method*

```
T GetValue()
```

The value, aborting when there is none.

The bargain `Dictionary.GetValue` and an array index make: asking for
something that is not there is a mistake in the caller rather than a
value to return. Use `GetValueOrDefault` where a miss is ordinary, and
`is Some x` where the answer decides what happens next.

**See also** &nbsp; [Optional.GetValueOrDefault](#getvalueordefault-method)

<sub>[stdlib/Standard.sl:201](../../stdlib/Standard.sl#L201)</sub>

#### GetValueOrDefault *method*

```
T GetValueOrDefault(T fallback)
```

The value if there is one, and `fallback` if there is not.

The reader that needs no proof, because it supplies its own -- the same
bargain `Result.GetValueOrDefault` makes.

**Parameters**

- `fallback` — what to answer when there is nothing held

**See also** &nbsp; [Optional.GetValue](#getvalue-method)

<sub>[stdlib/Standard.sl:220](../../stdlib/Standard.sl#L220)</sub>

#### Coalesce *method*

```
Optional<T> Coalesce(Optional<T> other)
```

This one if it holds anything, and `other` if it does not.

`other` is a value rather than something that produces one on demand.
A lambda would allocate a closure to save an evaluation, which is the
wrong way round at the sizes this is used at.

<sub>[stdlib/Standard.sl:232](../../stdlib/Standard.sl#L232)</sub>

#### Select *method*

```
Optional<R> Select<R>(Func<T, R> transform)
```

The value put through `transform`, or none.

    Optional<String> name = found.Select(i => people[i].Name);

The transform runs only where there is something to run it on, which is
the point: it is the `if` that would otherwise be written by hand.

**Type parameters**

- `R` — what `transform` produces

<sub>[stdlib/Standard.sl:247](../../stdlib/Standard.sl#L247)</sub>

#### SelectMany *method*

```
Optional<R> SelectMany<R>(Func<T, Optional<R>> transform)
```

`Select` for a transform that answers with an optional of its own, which
would otherwise nest one inside the other.

**Type parameters**

- `R` — what the transform's own optional holds

<sub>[stdlib/Standard.sl:258](../../stdlib/Standard.sl#L258)</sub>

#### Where *method*

```
Optional<T> Where(Predicate<T> keep)
```

This one when it holds something `keep` accepts, and none otherwise.

<sub>[stdlib/Standard.sl:266](../../stdlib/Standard.sl#L266)</sub>

#### InvokeIfPresent *method*

```
void InvokeIfPresent(Action<T> action)
```

Runs `action` on the value, if there is one.

<sub>[stdlib/Standard.sl:277](../../stdlib/Standard.sl#L277)</sub>

### Predicate&lt;T&gt; *closure*

```
closure bool Predicate<T>(T value)
```

Answers a question about a T.

**Type parameters**

- `T` — what the question is about

<sub>[stdlib/Standard.sl:95](../../stdlib/Standard.sl#L95)</sub>

### Result&lt;T, TError&gt; *variant*

```
variant Result<T, TError>
```

What an operation produced, or why it did not.

This is the language's answer to an exception. Stainless does not unwind, so
a function that can fail says so in its return type and the caller cannot
quietly ignore it: `Value` is unreadable until the compiler has seen `Ok`
checked, and `Error` unreadable until it has seen it fail.

```
Result<Config, IOError> Load(String path) {
    var text = File.ReadAllText(path);
    if (!text.Ok) { return Fail(text.Error); }
    return Ok(Parse(text.Value));
}
```

It is an ordinary variant, and every rule it appears to have is a rule
variants have. `Ok` and `Fail` are its two cases, so `r.Ok` asks the tag;
`Value` and `Error` are the fields those cases carry, so reading one needs
the compiler to have established which case is there; and both are written
without type arguments because a case takes its variant from where it is
going, the way a lambda takes its type from what it is assigned to.

Being a variant is also what makes it small. Only one case is ever present,
so the payloads overlap: a `Result<String, IOError>` is a tag and one
pointer, not a flag and both halves. Nothing allocates either way.

**Type parameters**

- `T` — what the call produces when it worked
- `TError` — why it did not, usually an enum so that a failure has a name rather than a number

<sub>[stdlib/Standard.sl:55](../../stdlib/Standard.sl#L55)</sub>

#### Ok *case*

```
Ok(T Value)
```

It worked, and `Value` is the answer.

<sub>[stdlib/Standard.sl:58](../../stdlib/Standard.sl#L58)</sub>

#### Fail *case*

```
Fail(TError Error)
```

It did not, and `Error` says why. The value is not there to be read --
that is the whole of what a variant buys over a pair.

<sub>[stdlib/Standard.sl:62](../../stdlib/Standard.sl#L62)</sub>

#### GetValueOrDefault *method*

```
T GetValueOrDefault(T fallback)
```

The value if there is one, and `fallback` if there is not.

The one reader that needs no proof, because it supplies its own: a
caller with a sensible default has nothing to check.

<sub>[stdlib/Standard.sl:68](../../stdlib/Standard.sl#L68)</sub>

