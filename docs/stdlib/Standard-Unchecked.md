# Standard.Unchecked

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Storage whose slots are not values yet: the one way to hold room for a
`T` that has no zero value.

A `String` is never null, so `new String[n]` is refused -- its elements
would start as nulls. A collection still needs spare capacity, and a slot
it has vacated still has to let go of what it held. These two functions are
that, and nothing else: an array whose slots are zero bytes, and a slot
put back to zero bytes.

**The obligation moves to whoever imports this.** A slot MUST be written
before it is read, and SHOULD be cleared when it is vacated so that what it
held is released. Nothing checks either. Reading a slot that was never
written hands out a null where the type says there is none, which is the
hole the rest of the language closes. `Array.Create` and `Array.Repeat` are
what a program that is not a collection wants instead.

Each compiles to exactly what `new T[n]` and `default(T)` compile to for a
type that has a zero value: one allocation, zeroed, and one store.

## Contents

**Functions** &nbsp; [ClearElement](#clearelement-function) &middot; [NewUninitializedArray](#newuninitializedarray-function)

## Functions

### ClearElement *function*

```
void ClearElement<T>(T[] array, nuint index)
```

Releases what a slot holds and puts it back to zero bytes, so the array no
longer keeps it alive. The slot MUST be written again before it is read.

**Parameters**

- `array` — the array the slot is in
- `index` — which slot; aborts when it is past the end

**Type parameters**

- `T` — the element type; nothing is asked of it

<sub>[stdlib/Unchecked/Unchecked.sl:56](../../stdlib/Unchecked/Unchecked.sl#L56)</sub>

### NewUninitializedArray *function*

```
T[] NewUninitializedArray<T>(nuint length)
```

An array of `length` slots holding zero bytes, which are not yet values of
`T` unless `T` has a zero value.

**Parameters**

- `length` — how many slots

**Type parameters**

- `T` — the element type; nothing is asked of it

**Returns** &nbsp; the array, every slot zero bytes

<sub>[stdlib/Unchecked/Unchecked.sl:48](../../stdlib/Unchecked/Unchecked.sl#L48)</sub>

