# Standard.Bits

<sub>Generated from the `///` blocks in the source by `stainless doc`. Edit the source, not this file.</sub>

Counting bits and rotating them.

These are here because they cannot be written in Stainless as well as the
target can do them. `LeadingZeroCount` is one instruction on every machine
this compiles for and about ten written out; `PopCount` is one instruction
where the target has it and the same arithmetic either way where it does
not, chosen per target rather than per author. A rotate written the obvious
way -- `(value << by) | (value >> (64 - by))` -- is worse than slow for a
count of zero: shifting by the width is undefined, so the answer is zero
rather than `value`. What is below is defined for every count.

The compiler declares the instructions ([Builtins](../../src/Stainless.Compiler/Binding/Builtins.cs))
and this file declares the same module again to put names on them, which is
the ordinary second declaration of §1.2.1 rather than anything special.

Everything takes and answers `uint` or `ulong`. A count comes back as `int`
because it is a small number and arithmetic on it should not be unsigned.

## Contents

**Functions** &nbsp; [IsPowerOfTwo](#ispoweroftwo-function) &middot; [IsPowerOfTwo](#ispoweroftwo-function) &middot; [LeadingZeroCount](#leadingzerocount-function) &middot; [LeadingZeroCount](#leadingzerocount-function) &middot; [Log2](#log2-function) &middot; [Log2](#log2-function) &middot; [MultiplyHigh](#multiplyhigh-function) &middot; [OpaqueCopy](#opaquecopy-function) &middot; [OpaqueCopy](#opaquecopy-function) &middot; [PopCount](#popcount-function) &middot; [PopCount](#popcount-function) &middot; [RotateLeft](#rotateleft-function) &middot; [RotateLeft](#rotateleft-function) &middot; [RotateRight](#rotateright-function) &middot; [RotateRight](#rotateright-function) &middot; [RoundUpToPowerOfTwo](#rounduptopoweroftwo-function) &middot; [RoundUpToPowerOfTwo](#rounduptopoweroftwo-function) &middot; [TrailingZeroCount](#trailingzerocount-function) &middot; [TrailingZeroCount](#trailingzerocount-function)

## Functions

### IsPowerOfTwo *function*

```
bool IsPowerOfTwo(uint value)
```

Whether exactly one bit is set, which is what makes a number a power of
two. Zero is not one.

<sub>[stdlib/Bits.sl:121](../../stdlib/Bits.sl#L121)</sub>

### IsPowerOfTwo *function*

```
bool IsPowerOfTwo(ulong value)
```

Whether exactly one bit is set. Zero is not a power of two.

<sub>[stdlib/Bits.sl:124](../../stdlib/Bits.sl#L124)</sub>

### LeadingZeroCount *function*

```
int LeadingZeroCount(uint value)
```

How many zero bits sit above the highest set bit: 32 for zero, 0 for any
value with its top bit set.

<sub>[stdlib/Bits.sl:51](../../stdlib/Bits.sl#L51)</sub>

### LeadingZeroCount *function*

```
int LeadingZeroCount(ulong value)
```

How many zero bits sit above the highest set bit: 64 for zero.

<sub>[stdlib/Bits.sl:54](../../stdlib/Bits.sl#L54)</sub>

### Log2 *function*

```
int Log2(uint value)
```

The position of the highest set bit, which is the floor of the base-2
logarithm.

Zero has no logarithm and no set bit to point at. This answers 0 for it,
as .NET does, rather than failing: every caller that reaches here with a
zero is sizing something and wants the smallest answer.

<sub>[stdlib/Bits.sl:114](../../stdlib/Bits.sl#L114)</sub>

### Log2 *function*

```
int Log2(ulong value)
```

The position of the highest set bit. Zero answers 0.

<sub>[stdlib/Bits.sl:117](../../stdlib/Bits.sl#L117)</sub>

### MultiplyHigh *function*

```
ulong MultiplyHigh(ulong left, ulong right)
```

The high 64 bits of the 128-bit product of `left` and `right`; `left * right`
is the low 64.

**See also** &nbsp; [Standard.Math.BigMul](Standard-Math.md#bigmul-function)

<sub>[stdlib/Bits.sl:90](../../stdlib/Bits.sl#L90)</sub>

### OpaqueCopy *function*

```
uint OpaqueCopy(uint value)
```

`value`, unchanged, as a value the optimiser knows nothing about.

For constant-time code. A mask computed from a secret — all ones or all
zeros — is exactly what an optimiser recognises and turns back into a
branch, which is the leak the mask was written to avoid. Passing it through
this first leaves the optimiser nothing to recognise. It costs no
instruction.

<sub>[stdlib/Bits.sl:101](../../stdlib/Bits.sl#L101)</sub>

### OpaqueCopy *function*

```
ulong OpaqueCopy(ulong value)
```

`value`, unchanged, as a value the optimiser knows nothing about.

<sub>[stdlib/Bits.sl:104](../../stdlib/Bits.sl#L104)</sub>

### PopCount *function*

```
int PopCount(uint value)
```

How many bits are set.

<sub>[stdlib/Bits.sl:44](../../stdlib/Bits.sl#L44)</sub>

### PopCount *function*

```
int PopCount(ulong value)
```

How many bits are set.

<sub>[stdlib/Bits.sl:47](../../stdlib/Bits.sl#L47)</sub>

### RotateLeft *function*

```
uint RotateLeft(uint value, int by)
```

The bits moved left, with what falls off the top arriving at the bottom.

The count is taken modulo the width, so rotating by 32 or by 64 is the
same as rotating by zero, which answers the value unchanged.

<sub>[stdlib/Bits.sl:69](../../stdlib/Bits.sl#L69)</sub>

### RotateLeft *function*

```
ulong RotateLeft(ulong value, int by)
```

The bits moved left, with what falls off the top arriving at the bottom.

<sub>[stdlib/Bits.sl:73](../../stdlib/Bits.sl#L73)</sub>

### RotateRight *function*

```
uint RotateRight(uint value, int by)
```

The bits moved right, with what falls off the bottom arriving at the top.

<sub>[stdlib/Bits.sl:77](../../stdlib/Bits.sl#L77)</sub>

### RotateRight *function*

```
ulong RotateRight(ulong value, int by)
```

The bits moved right, with what falls off the bottom arriving at the top.

<sub>[stdlib/Bits.sl:81](../../stdlib/Bits.sl#L81)</sub>

### RoundUpToPowerOfTwo *function*

```
uint RoundUpToPowerOfTwo(uint value)
```

The smallest power of two that is not below `value`.

Zero and one both answer one. A value above the largest power of two the
type holds answers zero, which is the wrap the shift produces and the only
answer available -- a caller sizing a table from untrusted input MUST check
for it.

<sub>[stdlib/Bits.sl:132](../../stdlib/Bits.sl#L132)</sub>

### RoundUpToPowerOfTwo *function*

```
ulong RoundUpToPowerOfTwo(ulong value)
```

The smallest power of two that is not below `value`. Zero and one both
answer one, and a value above the largest power of two answers zero.

<sub>[stdlib/Bits.sl:141](../../stdlib/Bits.sl#L141)</sub>

### TrailingZeroCount *function*

```
int TrailingZeroCount(uint value)
```

How many zero bits sit below the lowest set bit: 32 for zero, 0 for any
odd value.

<sub>[stdlib/Bits.sl:58](../../stdlib/Bits.sl#L58)</sub>

### TrailingZeroCount *function*

```
int TrailingZeroCount(ulong value)
```

How many zero bits sit below the lowest set bit: 64 for zero.

<sub>[stdlib/Bits.sl:61](../../stdlib/Bits.sl#L61)</sub>

