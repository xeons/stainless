# Standard

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

The language's own vocabulary: the markers and types that are rules rather
than library features, and so need no import to reach.

## Contents

**Types** &nbsp; [Action&lt;T&gt;](#actiont) &middot; [Comparer&lt;T&gt;](#comparert) &middot; [Fold&lt;A, T&gt;](#folda-t) &middot; [Func&lt;T, R&gt;](#funct-r) &middot; [Optional&lt;T&gt;](#optionalt) &middot; [Predicate&lt;T&gt;](#predicatet) &middot; [Result&lt;T, E&gt;](#resultt-e)

## Types

### Action&lt;T&gt; *closure*

```
closure void Action<T>(T value)
```

Does something with a T and returns nothing.

<sub>[stdlib/Standard.sl:86](../../stdlib/Standard.sl#L86)</sub>

### Comparer&lt;T&gt; *closure*

```
closure int Comparer<T>(T left, T right)
```

Orders two Ts: negative if `left` comes first, positive if `right` does,
zero if neither.

This is what lets a type be sorted more than one way, and what lets a type
that implements no interface be sorted at all.

<sub>[stdlib/Standard.sl:97](../../stdlib/Standard.sl#L97)</sub>

### Fold&lt;A, T&gt; *closure*

```
closure A Fold<A, T>(A total, T value)
```

Folds one T into a running A. Two parameters rather than one, because a
fold is the one shape that carries something along with it.

<sub>[stdlib/Standard.sl:90](../../stdlib/Standard.sl#L90)</sub>

### Func&lt;T, R&gt; *closure*

```
closure R Func<T, R>(T value)
```

Turns a T into an R. The transform half of `Map`.

<sub>[stdlib/Standard.sl:80](../../stdlib/Standard.sl#L80)</sub>

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

    if (map.IndexOf(key) is Some found) { return values.At(found.Value); }
    return fallback;

**Not a replacement for `C?`.** A nullable reference stays what it is: the
representation is already free there, and `if (c != null)` narrows without
a case to name. This is for everything a null pointer cannot say -- which
is also why the names differ: `Optional<T>` is this type, and "an optional"
is what the spec calls `C?`.

<sub>[stdlib/Standard.sl:125](../../stdlib/Standard.sl#L125)</sub>

#### None *case*

```
None
```

There is no value. Carries nothing, so there is nothing to read by
mistake.

<sub>[stdlib/Standard.sl:128](../../stdlib/Standard.sl#L128)</sub>

#### Some *case*

```
Some(T Value)
```

There is one, and `Some` carries it. Reached with `is Some x`, which
takes the value and names it in the same step.

<sub>[stdlib/Standard.sl:132](../../stdlib/Standard.sl#L132)</sub>

#### HasValue *method*

```
bool HasValue()
```

True when there is a value. The reader for a caller that is about to
ask a second question anyway; `is Some x` is the one that gets at it.

<sub>[stdlib/Standard.sl:136](../../stdlib/Standard.sl#L136)</sub>

#### IsEmpty *method*

```
bool IsEmpty()
```

True when there is not. The same question the other way round, because
`!x.HasValue()` reads worse than the thing it means.

<sub>[stdlib/Standard.sl:143](../../stdlib/Standard.sl#L143)</sub>

#### Get *method*

```
T Get()
```

The value, aborting when there is none.

The bargain `Dictionary.Get` and an array index make: asking for
something that is not there is a mistake in the caller rather than a
value to return. Use `ValueOr` where a miss is ordinary, and
`is Some x` where the answer decides what happens next.

<sub>[stdlib/Standard.sl:154](../../stdlib/Standard.sl#L154)</sub>

#### ValueOr *method*

```
T ValueOr(T fallback)
```

The value if there is one, and `fallback` if there is not.

The reader that needs no proof, because it supplies its own -- the same
bargain `Result.ValueOr` makes.

<sub>[stdlib/Standard.sl:168](../../stdlib/Standard.sl#L168)</sub>

#### Or *method*

```
Optional<T> Or(Optional<T> other)
```

This one if it holds anything, and `other` if it does not.

`other` is a value rather than something that produces one on demand.
A lambda would allocate a closure to save an evaluation, which is the
wrong way round at the sizes this is used at.

<sub>[stdlib/Standard.sl:178](../../stdlib/Standard.sl#L178)</sub>

#### Map *method*

```
Optional<R> Map<R>(Func<T, R> transform)
```

The value put through `transform`, or none.

    Optional<String> name = found.Map(i => people.At(i).Name);

The transform runs only where there is something to run it on, which is
the point: it is the `if` that would otherwise be written by hand.

<sub>[stdlib/Standard.sl:189](../../stdlib/Standard.sl#L189)</sub>

#### FlatMap *method*

```
Optional<R> FlatMap<R>(Func<T, Optional<R>> transform)
```

`Map` for a transform that answers with an optional of its own, which
would otherwise nest one inside the other.

<sub>[stdlib/Standard.sl:196](../../stdlib/Standard.sl#L196)</sub>

#### Filter *method*

```
Optional<T> Filter(Predicate<T> keep)
```

This one when it holds something `keep` accepts, and none otherwise.

<sub>[stdlib/Standard.sl:202](../../stdlib/Standard.sl#L202)</sub>

#### IfPresent *method*

```
void IfPresent(Action<T> action)
```

Runs `action` on the value, if there is one.

<sub>[stdlib/Standard.sl:210](../../stdlib/Standard.sl#L210)</sub>

### Predicate&lt;T&gt; *closure*

```
closure bool Predicate<T>(T value)
```

Answers a question about a T.

<sub>[stdlib/Standard.sl:83](../../stdlib/Standard.sl#L83)</sub>

### Result&lt;T, E&gt; *variant*

```
variant Result<T, E>
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

<sub>[stdlib/Standard.sl:51](../../stdlib/Standard.sl#L51)</sub>

#### Ok *case*

```
Ok(T Value)
```

It worked, and `Value` is the answer.

<sub>[stdlib/Standard.sl:53](../../stdlib/Standard.sl#L53)</sub>

#### Fail *case*

```
Fail(E Error)
```

It did not, and `Error` says why. The value is not there to be read --
that is the whole of what a variant buys over a pair.

<sub>[stdlib/Standard.sl:57](../../stdlib/Standard.sl#L57)</sub>

#### ValueOr *method*

```
T ValueOr(T fallback)
```

The value if there is one, and `fallback` if there is not.

The one reader that needs no proof, because it supplies its own: a
caller with a sensible default has nothing to check.

<sub>[stdlib/Standard.sl:63](../../stdlib/Standard.sl#L63)</sub>

