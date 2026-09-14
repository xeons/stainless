# Standard.Random

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Pseudo-random numbers.

A class rather than a set of free functions, and deliberately: the state has
to live somewhere, the language has no mutable global to put it in, and a
hidden one shared by every caller is what makes a program impossible to
reproduce. A `Random` you made is a `Random` you can seed and replay.

**This is not cryptographic.** xoshiro256** is fast and well-distributed,
and its entire future is computable from 256 bits of state -- which is what
makes a seeded run reproducible and what makes it unfit for a key, a token
or a password. `Bytes` from the platform is what that needs; `sl_random_bytes`
is what this seeds from and is right there.

## Contents

**Types** &nbsp; [Random](#random-class)

**Functions** &nbsp; [Bytes](#bytes-function) &middot; [Seed](#seed-function)

## Types

### Random *class*

```
class Random
```

xoshiro256**, which is the current answer for a general-purpose generator:
four words of state, no multiply in the step, and it passes the test suites
that killed the older ones.

<sub>[stdlib/Random.sl:46](../../stdlib/Random.sl#L46)</sub>

#### NextULong *method*

```
ulong NextULong()
```

The next 64 bits. Every other method here is built on this one.

<sub>[stdlib/Random.sl:95](../../stdlib/Random.sl#L95)</sub>

#### NextLong *method*

```
long NextLong()
```

The next 64 bits read as signed, so negative half the time. Reach for
`NextBelow` when a range is what is wanted.

<sub>[stdlib/Random.sl:111](../../stdlib/Random.sl#L111)</sub>

#### NextBelow *method*

```
ulong NextBelow(ulong limit)
```

A number in `[0, limit)`. Aborts on a limit of zero, which names an
empty range and has no answer.

Rejection rather than a modulo: `NextULong() % limit` is biased toward
the low end whenever the limit does not divide 2^64, and the bias is
large exactly when the limit is large. The loop discards the short tail
instead, and runs more than once with probability below one half.

<sub>[stdlib/Random.sl:120](../../stdlib/Random.sl#L120)</sub>

#### NextBetween *method*

```
long NextBetween(long low, long high)
```

A number in `[low, high)`. Aborts when the range is empty.

<sub>[stdlib/Random.sl:132](../../stdlib/Random.sl#L132)</sub>

#### NextInt *method*

```
int NextInt(int limit)
```

A number in `[0, limit)`, for the common case of an `int`.

<sub>[stdlib/Random.sl:138](../../stdlib/Random.sl#L138)</sub>

#### NextBool *method*

```
bool NextBool()
```

True about half the time.

<sub>[stdlib/Random.sl:141](../../stdlib/Random.sl#L141)</sub>

#### NextDouble *method*

```
double NextDouble()
```

A double in `[0, 1)`.

The top 53 bits, which is exactly the precision a double has: taking
fewer would leave gaps, and taking more would round some draws up to
1.0 and break the half-open range.

<sub>[stdlib/Random.sl:148](../../stdlib/Random.sl#L148)</sub>

#### NextBytes *method*

```
void NextBytes(byte[] buffer)
```

Fills an array with random bytes.

<sub>[stdlib/Random.sl:153](../../stdlib/Random.sl#L153)</sub>

#### Shuffle *method*

```
void Shuffle(long[] items)
```

Reorders an array in place, every ordering equally likely.

Fisher-Yates, walking down: element i is swapped with a uniformly
chosen element at or below it. Walking up, or choosing from the whole
array each time, is the classic wrong version -- it produces n^n equally
likely paths over n! orderings, which cannot come out even.

<sub>[stdlib/Random.sl:170](../../stdlib/Random.sl#L170)</sub>

## Functions

### Bytes *function*

```
bool Bytes(byte[] buffer)
```

Bytes straight from the operating system's cryptographic source, which is
what a key or a token wants. Reports whether it managed; a false is not a
reason to fall back on the clock.

<sub>[stdlib/Random.sl:185](../../stdlib/Random.sl#L185)</sub>

### Seed *function*

```
long Seed()
```

One unpredictable 64-bit value from the platform, for seeding something
else deliberately. Aborts if the platform supplies none; `Bytes` is the
form that reports instead.

<sub>[stdlib/Random.sl:193](../../stdlib/Random.sl#L193)</sub>

