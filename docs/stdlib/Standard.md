# Standard

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

The language's own vocabulary: the markers and types that are rules rather
than library features, and so need no import to reach.

## Contents

**Types** &nbsp; [Action&lt;T&gt;](#actiont-closure) &middot; [Comparison&lt;T&gt;](#comparisont-closure) &middot; [Fold&lt;TAccumulate, TSource&gt;](#foldtaccumulate-tsource-closure) &middot; [Func&lt;T, TResult&gt;](#funct-tresult-closure) &middot; [Optional&lt;T&gt;](#optionalt-variant) &middot; [Predicate&lt;T&gt;](#predicatet-closure) &middot; [Result&lt;T, TError&gt;](#resultt-terror-variant)

## Types

### Action&lt;T&gt; *closure*

```
closure void Action<T>(T value)
```

Does something with a T and returns nothing.

**Type parameters**

- `T` — what is handed to it

<sub>[stdlib/Standard/Standard.sl:48](../../stdlib/Standard/Standard.sl#L48)</sub>

### Comparison&lt;T&gt; *closure*

```
closure int Comparison<T>(T left, T right)
```

Orders two Ts: negative if `left` comes first, positive if `right` does,
zero if neither.

This is what lets a type be sorted more than one way, and what lets a type
that implements no interface be sorted at all.

**Type parameters**

- `T` — what is being ordered

<sub>[stdlib/Standard/Standard.sl:66](../../stdlib/Standard/Standard.sl#L66)</sub>

### Fold&lt;TAccumulate, TSource&gt; *closure*

```
closure TAccumulate Fold<TAccumulate, TSource>(TAccumulate total, TSource value)
```

Folds one element into a running total. Two parameters rather than one,
because a fold is the one shape that carries something along with it.

**Parameters**

- `total` — what has been accumulated so far
- `value` — the next element to fold in

**Type parameters**

- `TAccumulate` — what is carried along, and what the fold answers with
- `TSource` — what is folded over

<sub>[stdlib/Standard/Standard.sl:57](../../stdlib/Standard/Standard.sl#L57)</sub>

### Func&lt;T, TResult&gt; *closure*

```
closure TResult Func<T, TResult>(T value)
```

Turns a T into a TResult. The transform half of `Select`.

**Type parameters**

- `T` — what goes in
- `TResult` — what comes out

<sub>[stdlib/Standard/Standard.sl:38](../../stdlib/Standard/Standard.sl#L38)</sub>

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

<sub>[stdlib/Standard/Optional.sl:46](../../stdlib/Standard/Optional.sl#L46)</sub>

#### None *case*

```
None
```

There is no value. Carries nothing, so there is nothing to read by
mistake.

<sub>[stdlib/Standard/Optional.sl:50](../../stdlib/Standard/Optional.sl#L50)</sub>

#### Some *case*

```
Some(T Value)
```

There is one, and `Some` carries it. Reached with `is Some x`, which
takes the value and names it in the same step.

<sub>[stdlib/Standard/Optional.sl:54](../../stdlib/Standard/Optional.sl#L54)</sub>

#### HasValue *property*

```
bool HasValue { get; }
```

True when there is a value. The reader for a caller that is about to
ask a second question anyway; `is Some x` is the one that gets at it.

<sub>[stdlib/Standard/Optional.sl:58](../../stdlib/Standard/Optional.sl#L58)</sub>

#### IsEmpty *property*

```
bool IsEmpty { get; }
```

True when there is not. The same question the other way round, because
`!x.HasValue` reads worse than the thing it means.

<sub>[stdlib/Standard/Optional.sl:70](../../stdlib/Standard/Optional.sl#L70)</sub>

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

<sub>[stdlib/Standard/Optional.sl:88](../../stdlib/Standard/Optional.sl#L88)</sub>

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

<sub>[stdlib/Standard/Optional.sl:107](../../stdlib/Standard/Optional.sl#L107)</sub>

#### Coalesce *method*

```
Optional<T> Coalesce(Optional<T> other)
```

This one if it holds anything, and `other` if it does not.

`other` is a value rather than something that produces one on demand.
A lambda would allocate a closure to save an evaluation, which is the
wrong way round at the sizes this is used at.

<sub>[stdlib/Standard/Optional.sl:119](../../stdlib/Standard/Optional.sl#L119)</sub>

#### Select *method*

```
Optional<TResult> Select<TResult>(Func<T, TResult> transform)
```

The value put through `transform`, or none.

    Optional<String> name = found.Select(i => people[i].Name);

The transform runs only where there is something to run it on, which is
the point: it is the `if` that would otherwise be written by hand.

**Type parameters**

- `TResult` — what `transform` produces

<sub>[stdlib/Standard/Optional.sl:134](../../stdlib/Standard/Optional.sl#L134)</sub>

#### SelectMany *method*

```
Optional<TResult> SelectMany<TResult>(Func<T, Optional<TResult>> transform)
```

`Select` for a transform that answers with an optional of its own, which
would otherwise nest one inside the other.

**Type parameters**

- `TResult` — what the transform's own optional holds

<sub>[stdlib/Standard/Optional.sl:145](../../stdlib/Standard/Optional.sl#L145)</sub>

#### Where *method*

```
Optional<T> Where(Predicate<T> keep)
```

This one when it holds something `keep` accepts, and none otherwise.

<sub>[stdlib/Standard/Optional.sl:153](../../stdlib/Standard/Optional.sl#L153)</sub>

#### InvokeIfPresent *method*

```
void InvokeIfPresent(Action<T> action)
```

Runs `action` on the value, if there is one.

<sub>[stdlib/Standard/Optional.sl:164](../../stdlib/Standard/Optional.sl#L164)</sub>

### Predicate&lt;T&gt; *closure*

```
closure bool Predicate<T>(T value)
```

Answers a question about a T.

**Type parameters**

- `T` — what the question is about

<sub>[stdlib/Standard/Standard.sl:43](../../stdlib/Standard/Standard.sl#L43)</sub>

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

<sub>[stdlib/Standard/Result.sl:53](../../stdlib/Standard/Result.sl#L53)</sub>

#### Ok *case*

```
Ok(T Value)
```

It worked, and `Value` is the answer.

<sub>[stdlib/Standard/Result.sl:56](../../stdlib/Standard/Result.sl#L56)</sub>

#### Fail *case*

```
Fail(TError Error)
```

It did not, and `Error` says why. The value is not there to be read --
that is the whole of what a variant buys over a pair.

<sub>[stdlib/Standard/Result.sl:60](../../stdlib/Standard/Result.sl#L60)</sub>

#### GetValueOrDefault *method*

```
T GetValueOrDefault(T fallback)
```

The value if there is one, and `fallback` if there is not.

The one reader that needs no proof, because it supplies its own: a
caller with a sensible default has nothing to check.

<sub>[stdlib/Standard/Result.sl:66](../../stdlib/Standard/Result.sl#L66)</sub>

