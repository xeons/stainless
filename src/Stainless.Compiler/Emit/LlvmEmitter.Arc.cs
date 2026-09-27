// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

using System.Globalization;
using System.Text;
using Stainless.Binding;
using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Emit;

/// <summary>
/// Retain and release, and everything that decides where they go.
///
/// Every reference-counting decision in the compiler is made here.
/// Which function a retain calls depends on what is being retained --
/// an object, a weak reference or a COM interface -- and open-coding
/// that anywhere else is how the three drift apart.
/// </summary>
public sealed partial class LlvmEmitter
{
    // ============================================================ ownership

    /// <summary>
    /// Emits an expression whose value the caller only reads. An owned value
    /// is registered for release when the statement ends.
    /// </summary>
    private Val EmitExpression(BoundExpression expression) => Borrow(EmitOwnable(expression));

    /// <summary>
    /// Emits an expression whose value the caller keeps: +1, or nothing to
    /// count. The caller MUST consume it before anything else is evaluated.
    /// </summary>
    private Val EmitOwned(BoundExpression expression) => Take(EmitOwnable(expression));

    /// <summary>
    /// Emits an expression and hands back whatever it owes. The caller MUST
    /// pass an owned value to <see cref="Borrow"/> or <see cref="Take"/>, or
    /// consume it in a way of its own and say so with <see cref="Consume"/>.
    /// </summary>
    private Val EmitOwnable(BoundExpression expression)
    {
        var value = EmitValue(expression);

#if DEBUG
        if (expression.Type.CarriesReferences() &&
            (value.Hold == Hold.Owned) != (HoldOf(expression) == Hold.Owned))
            throw new InternalCompilerError(
                $"the emitter made a {value.Hold} value where {expression.GetType().Name} " +
                $"yields a {HoldOf(expression)} one", expression.Span);
#endif

        return value;
    }

    /// <summary>
    /// What an expression's value owes, from the node alone. The emitter of
    /// each node decides this for itself, and a Debug build checks that the
    /// two agree.
    /// </summary>
    private static Hold HoldOf(BoundExpression expression) => expression switch
    {
        BoundNullLiteral or BoundStringLiteral or BoundUtf8Literal
            or BoundDefault or BoundUnmatchedSwitch => Hold.Uncounted,
        BoundInterpolatedString { Parts.Count: 0 } => Hold.Uncounted,
        BoundClosureCreate { Receiver: null } => Hold.Uncounted,

        BoundCall or BoundIndirectCall or BoundClosureCall or BoundNew or BoundStructNew
            or BoundClosure or BoundClosureCreate or BoundNewArray or BoundTupleCreate
            or BoundVariantConstruction or BoundInterpolatedString or BoundSlice => Hold.Owned,

        // One in the frame ends with its statement, so nothing may keep it.
        BoundArrayLiteral literal => literal.OnStack ? Hold.Borrowed : Hold.Owned,

        BoundConditional chosen =>
            HoldOf(chosen.WhenTrue) == Hold.Uncounted && HoldOf(chosen.WhenFalse) == Hold.Uncounted
                ? Hold.Uncounted
                : Hold.Owned,

        BoundSequence sequence => HoldOf(sequence.Value),
        BoundLet held when HandsOnLocal(held) && HoldOf(held.Value) == Hold.Owned => Hold.Owned,
        BoundLet held => HoldOf(held.Body),
        BoundTry attempt => HoldOf(attempt.OnSuccess),
        BoundConversion conversion => HoldOfConversion(conversion),
        _ => Hold.Borrowed,
    };

    private static Hold HoldOfConversion(BoundConversion conversion) => conversion.Kind switch
    {
        ConversionKind.ArrayToSlice or ConversionKind.ComAdopt or ConversionKind.ComQuery => Hold.Owned,

        // A strong reference out of a weak one is a new +1, or null.
        ConversionKind.ReferenceToOptional when conversion.Operand.Type is WeakTypeSymbol => Hold.Owned,

        _ when PassesOwnership(conversion) => HoldOf(conversion.Operand),
        _ => Hold.Borrowed,
    };

    /// <summary>
    /// True for a conversion whose value is the operand's own pointer, counted
    /// the same way, so that what the operand owed the result owes instead.
    ///
    /// Not <c>ReferenceToWeak</c>: the same pointer, but a weak slot keeps it
    /// with a weak count, and the strong one the operand owed is still owed.
    /// </summary>
    private static bool PassesOwnership(BoundConversion conversion) =>
        conversion.Kind is ConversionKind.Identity or ConversionKind.PointerCast
            or ConversionKind.NullToReference or ConversionKind.ClassToInterface
            or ConversionKind.NarrowOptional or ConversionKind.Upcast
            or ConversionKind.TestedReference or ConversionKind.Downcast
            or ConversionKind.ComUpcast or ConversionKind.ReferenceToOptional
        && !(conversion.Kind == ConversionKind.ReferenceToOptional
             && conversion.Operand.Type is WeakTypeSymbol)
        && CountedAlike(conversion.Operand.Type, conversion.Type);

    /// <summary>True when a +1 of one type is a +1 of the other.</summary>
    private static bool CountedAlike(TypeSymbol first, TypeSymbol second) =>
        first.CarriesReferences() == second.CarriesReferences()
        && (!first.CarriesReferences() || RetainOf(first) == RetainOf(second));

    /// <summary>
    /// True when a <c>let</c> evaluates to the very object it named, and
    /// nothing in between replaces the name: an initializer's
    /// <c>let made = new C() in (made.X = 1, made)</c>. What made the value
    /// is then what the whole hands on.
    /// </summary>
    private static bool HandsOnLocal(BoundLet held) =>
        !held.IsOwned && Yields(held.Body, held.Local) && !LocalWriteFinder.Writes(held.Body, held.Local);

    private static bool Yields(BoundExpression expression, LocalSymbol local) => expression switch
    {
        BoundLocalAccess read => ReferenceEquals(read.Local, local),
        BoundSequence sequence => Yields(sequence.Value, local),
        BoundLet inner => Yields(inner.Body, local),
        BoundConversion conversion => PassesOwnership(conversion) && Yields(conversion.Operand, local),
        _ => false,
    };

    /// <summary>A value this code made at +1, which the caller now owes.</summary>
    private Val Fresh(Val value)
    {
        if (!value.Type.CarriesReferences()) return value;

        Unsettle(value.Ref);
        return value with { Hold = Hold.Owned };
    }

    /// <summary>A value with nothing to count, which is moved and dropped for free.</summary>
    private static Val Uncounted(Val value) => value with { Hold = Hold.Uncounted };

    /// <summary>
    /// The value to read and not keep: an owned one is registered for release
    /// when the statement ends, and is borrowed from there.
    /// </summary>
    private Val Borrow(Val value)
    {
        if (value.Hold != Hold.Owned) return value;

        Consume(value);
        TrackTemporary(value.Ref, value.Type);
        return value with { Hold = Hold.Borrowed };
    }

    /// <summary>
    /// The value at +1: an owned one as it is, a borrowed one retained. A
    /// borrowed struct is copied first, so that what is owned is at an address
    /// nothing else writes -- the one it was read from may be written before
    /// the copy is consumed.
    /// </summary>
    private Val Take(Val value)
    {
        switch (value.Hold)
        {
            case Hold.Owned:
                Consume(value);
                return value;
            case Hold.Uncounted:
                return value;
        }

        if (!value.Type.CarriesReferences()) return value;

        if (value.Type is StructTypeSymbol structType)
        {
            string copy = Alloca(LlvmTypeOf(structType), "owned");
            MemCopy(copy, value.Ref, structType.Size);
            RetainFieldsAt(copy, structType);
            return value with { Ref = copy, Hold = Hold.Owned };
        }

        Retain(value.Ref, value.Type);
        return value with { Hold = Hold.Owned };
    }

    /// <summary>
    /// Takes back a value <see cref="Borrow"/> registered for release, whose +1
    /// the caller now hands on. Registering first is what releases it if a
    /// <c>try</c> returns before it is handed on.
    /// </summary>
    private void Reclaim(Val registered)
    {
        int at = _pendingReleases.FindLastIndex(p => p.Ref == registered.Ref);
        if (at < 0)
            throw new InternalCompilerError($"{registered.Ref} is not waiting to be released");

        _pendingReleases.RemoveAt(at);
    }

    /// <summary>
    /// Registers an aggregate being built for release, so that a <c>try</c>
    /// returning partway through lets go of what went in so far.
    /// </summary>
    private Val Building(Val made)
    {
        if (made.Type.CarriesReferences()) TrackTemporary(made.Ref, made.Type);
        return made;
    }

    /// <summary>The aggregate <see cref="Building"/> began, finished and at +1.</summary>
    private Val Built(Val made)
    {
        if (!made.Type.CarriesReferences()) return made;

        Reclaim(made);
        return Fresh(made);
    }

    /// <summary>
    /// Says that an owned value has been consumed: stored, merged, returned,
    /// or made immortal.
    /// </summary>
    private void Consume(Val value)
    {
#if DEBUG
        if (value.Hold == Hold.Owned && !_unsettled.Remove(value.Ref))
            throw new InternalCompilerError($"{value.Ref} was consumed twice");
#endif
    }

    private void Unsettle(string reference)
    {
#if DEBUG
        if (!_unsettled.Add(reference))
            throw new InternalCompilerError($"{reference} was made owned twice");
#endif
    }

    /// <summary>
    /// Stores an owned value into a slot that owns what it holds, and drops
    /// what the slot held. The value is stored before the old one is
    /// released, so a destructor that reads the slot finds the new value.
    /// </summary>
    private void MoveInto(string slot, Val value, TypeSymbol targetType)
    {
        if (targetType is StructTypeSymbol structType)
        {
            if (structType.CarriesReferences()) ReleaseFieldsAt(slot, structType);
            MemCopy(slot, value.Ref, structType.Size);
            return;
        }

        if (targetType.IsManagedSlot())
        {
            string old = Emit("ptr", $"load ptr, ptr {slot}");
            Line($"store ptr {value.Ref}, ptr {slot}");
            Release(old, targetType);
            return;
        }

        StoreUncounted(slot, value, targetType);
    }

    /// <summary>The same into a slot that holds nothing yet: zeroed storage.</summary>
    private void InitializeWith(string slot, Val value, TypeSymbol targetType)
    {
        if (targetType is StructTypeSymbol structType)
        {
            MemCopy(slot, value.Ref, structType.Size);
            return;
        }

        if (targetType.IsManagedSlot())
        {
            Line($"store ptr {value.Ref}, ptr {slot}");
            return;
        }

        StoreUncounted(slot, value, targetType);
    }

    /// <summary>
    /// Stores a value that is only borrowed: retain the new value, release the
    /// old one, in that order, so <c>x = x</c> cannot destroy the object
    /// mid-assignment.
    /// </summary>
    private void StoreInto(string slot, Val value, TypeSymbol targetType)
    {
        if (targetType is StructTypeSymbol structType)
        {
            if (structType.CarriesReferences())
            {
                RetainFieldsAt(value.Ref, structType);
                ReleaseFieldsAt(slot, structType);
            }

            MemCopy(slot, value.Ref, structType.Size);
            return;
        }

        if (targetType.IsManagedSlot())
        {
            Retain(value.Ref, targetType);
            string old = Emit("ptr", $"load ptr, ptr {slot}");
            Release(old, targetType);
            Line($"store ptr {value.Ref}, ptr {slot}");
            return;
        }

        StoreUncounted(slot, value, targetType);
    }

    /// <summary>
    /// A value with nothing inside it to count. An inline array is held by
    /// address, like a struct, and cannot hold a reference (SL0486), so the
    /// whole of it is copied as bytes.
    /// </summary>
    private void StoreUncounted(string slot, Val value, TypeSymbol targetType)
    {
        if (targetType is FixedArrayTypeSymbol inline)
        {
            MemCopy(slot, value.Ref, inline.Size);
            return;
        }

        Line($"store {LlvmTypeOf(targetType)} {value.Ref}, ptr {slot}");
    }

    /// <summary>
    /// Emits an expression in a block of its own, whose temporaries are
    /// released before it ends: the block that merges it is also reached from
    /// somewhere it never ran, so a release there would not be dominated by
    /// what it releases. What the expression yields is kept, at +1.
    /// </summary>
    private Val EmitBranch(BoundExpression expression)
    {
        int mark = _pendingReleases.Count;
        var value = EmitOwned(expression);
        FlushTemporaries(mark);
        return value;
    }

    // ============================================================ ARC

    private void PushScope() => _scopes.Add([]);

    private void PopScopeWithoutRelease() => _scopes.RemoveAt(_scopes.Count - 1);

    private void TrackOwnedLocal(string slot, TypeSymbol type)
    {
        if (!type.CarriesReferences()) return;

        _scopes[^1].Add((slot, type));
        if (_hasLabels) _clearedOnRelease.Add(slot);
    }

    /// <summary>Releases every owned local from the innermost scope down to <paramref name="depth"/>.</summary>
    private void ReleaseScopes(int depth)
    {
        for (int i = _scopes.Count - 1; i >= depth; i--)
            foreach (var (slot, type) in Enumerable.Reverse(_scopes[i]))
                ReleaseSlot(slot, type);
    }

    private void ReleaseCurrentScope()
    {
        foreach (var (slot, type) in Enumerable.Reverse(_scopes[^1]))
            ReleaseSlot(slot, type);
    }

    /// <summary>
    /// Drops what a storage slot owns: the reference it holds, or, for a struct,
    /// every reference inside it.
    /// </summary>
    private void ReleaseSlot(string slot, TypeSymbol type)
    {
        bool clear = _clearedOnRelease.Contains(slot);

        if (type is StructTypeSymbol structType)
        {
            ReleaseFieldsAt(slot, structType);
            if (clear)
                Line($"store {StructName(structType)} zeroinitializer, ptr {slot}");
            return;
        }

        string value = Emit("ptr", $"load ptr, ptr {slot}");
        Release(value, type);
        if (clear)
            Line($"store ptr null, ptr {slot}");
    }

    /// <summary>
    /// Retains every reference inside the struct at <paramref name="address"/>,
    /// recursing through struct fields.
    ///
    /// This is what a struct copy costs once it holds a reference. It is the
    /// price of lifting the old rule that a struct was always raw bytes, and it
    /// is charged only to structs that actually hold one — a struct of plain
    /// data still copies with a memcpy and nothing else.
    /// </summary>
    private void RetainFieldsAt(string address, StructTypeSymbol structType) =>
        WalkReferences(address, structType, (slot, type) =>
        {
            if (type is VariantTypeSymbol variant)
            {
                Line($"call void @{VariantArcName(variant, retaining: true)}(ptr {slot})");
                return;
            }

            string value = Emit("ptr", $"load ptr, ptr {slot}");
            Retain(value, type);
        });

    /// <summary>Releases every reference inside the struct at <paramref name="address"/>.</summary>
    private void ReleaseFieldsAt(string address, StructTypeSymbol structType) =>
        WalkReferences(address, structType, (slot, type) =>
        {
            if (type is VariantTypeSymbol variant)
            {
                Line($"call void @{VariantArcName(variant, retaining: false)}(ptr {slot})");
                return;
            }

            string value = Emit("ptr", $"load ptr, ptr {slot}");
            Release(value, type);
        });

    /// <summary>
    /// Visits the address of every counted reference inside a struct value,
    /// descending into struct fields so a nested one is not missed.
    ///
    /// A variant is handed to the visitor whole rather than walked. Which of
    /// its references are really there is a question about the tag, and the
    /// answer is a branch at run time rather than a list at compile time — so
    /// it goes to a function of its own that the visitor calls.
    /// </summary>
    private void WalkReferences(
        string address, StructTypeSymbol structType, Action<string, TypeSymbol> visit)
    {
        if (structType is VariantTypeSymbol self)
        {
            visit(address, self);
            return;
        }

        foreach (var field in structType.Fields)
        {
            if (!field.Type.CarriesReferences()) continue;

            string slot = StructFieldAddress(address, structType, field);

            if (field.Type is VariantTypeSymbol nestedVariant) visit(slot, nestedVariant);
            else if (field.Type is StructTypeSymbol nested) WalkReferences(slot, nested, visit);
            else visit(slot, field.Type);
        }
    }

    private static string VariantArcName(VariantTypeSymbol variant, bool retaining) =>
        (retaining ? "_SLvretain_" : "_SLvrelease_") + Mangler.SymbolSafe(variant.QualifiedName);

    /// <summary>
    /// The two functions that copy and drop a variant's references.
    ///
    /// A struct's references are a list the compiler can write out; a variant's
    /// are whichever case is in the tag, so this is a switch. Only the case
    /// actually present is touched, which is the whole reason the payloads may
    /// overlap: nothing ever retains or releases through the bytes of a case
    /// that is not there.
    ///
    /// A variant no case of which holds a reference gets no function at all,
    /// because nothing asks for one — <c>CarriesReferences</c> is false for it,
    /// and it copies as plain bytes like any other struct.
    /// </summary>
    private void EmitVariantArcThunks(VariantTypeSymbol variant)
    {
        foreach (bool retaining in (bool[])[true, false])
        {
            ResetFunctionState();
            _module.AppendLine(
                $"define internal void @{VariantArcName(variant, retaining)}(ptr %value)"
                + FrameAttributes + " {");
            _body.Clear();
            _blockTerminated = false;

            string tag = Emit("i8",
                $"load i8, ptr {Emit("ptr", $"getelementptr inbounds {StructName(variant)}, " +
                                           "ptr %value, i32 0, i32 0")}");

            string endLabel = NextLabel("variant.done");
            var arms = new List<(VariantCaseSymbol Case, string Label)>();

            foreach (var variantCase in variant.Cases)
            {
                if (variantCase.Payload is not { } payload) continue;
                if (!payload.Fields.Any(f => f.Type.CarriesReferences())) continue;

                arms.Add((variantCase, NextLabel("variant.case")));
            }

            Terminator($"switch i8 {tag}, label %{endLabel} [ " +
                       string.Join(" ", arms.Select(a => $"i8 {a.Case.Tag}, label %{a.Label}")) +
                       " ]");

            foreach (var (variantCase, label) in arms)
            {
                Label(label);

                string address = Emit("ptr",
                    $"getelementptr inbounds {StructName(variant)}, ptr %value, i32 0, i32 1");

                if (retaining) RetainFieldsAt(address, variantCase.Payload!);
                else ReleaseFieldsAt(address, variantCase.Payload!);

                Terminator($"br label %{endLabel}");
            }

            Label(endLabel);
            Terminator("ret void");

            _module.AppendLine("entry:");
            _module.Append(_entryAllocas);
            _module.Append(_body);
            _module.AppendLine("}");
            _module.AppendLine();
        }
    }

    /// <summary>Registers a +1 value for release once the current statement finishes.</summary>
    ///
    /// <remarks>
    /// A <c>[NoUnknown]</c> com interface has no +1 to drop: releasing one
    /// would call whatever its vtable has where Release would be. The guard is
    /// here rather than at each caller because there is nothing any of them
    /// could usefully do instead.
    ///
    /// It names that case rather than asking <c>NeedsArc</c>, which is a
    /// narrower question than this one: a slice and a struct holding a
    /// reference both answer false to it and both are tracked here.
    /// </remarks>
    private void TrackTemporary(string reference, TypeSymbol type)
    {
        if (type is ComInterfaceTypeSymbol { HasUnknown: false } or
            OptionalTypeSymbol { Element: ComInterfaceTypeSymbol { HasUnknown: false } })
            return;

        _pendingReleases.Add((reference, type));
    }

    private void FlushTemporaries(int from = 0)
    {
        var onStack = new List<string>();

        for (int i = from; i < _pendingReleases.Count; i++)
        {
            var (reference, type) = _pendingReleases[i];

            // Last, once every slice of it has let go.
            if (_stackArrays.Contains(reference))
            {
                onStack.Add(reference);
                continue;
            }

            // A struct temporary is held by address, so what is dropped is what
            // lies inside it rather than the pointer itself.
            if (type is StructTypeSymbol structType)
            {
                ReleaseFieldsAt(reference, structType);
                continue;
            }

            Release(reference, type);
        }

        // Newest first: a later one's elements may hold an earlier one.
        for (int i = onStack.Count - 1; i >= 0; i--)
            EndStackArray(onStack[i]);

        _pendingReleases.RemoveRange(from, _pendingReleases.Count - from);
    }

    /// <summary>
    /// True when a slot of this type is counted by COM rather than by the
    /// runtime's own header. An optional one still is: <c>IFoo?</c> is the same
    /// pointer, allowed to be null.
    /// </summary>
    private static bool IsComReference(TypeSymbol type) =>
        type is ComInterfaceTypeSymbol or OptionalTypeSymbol { Element: ComInterfaceTypeSymbol };

    /// <summary>
    /// The runtime function that adds a reference to a value of this type.
    ///
    /// Three kinds of counting, one decision. A COM reference goes through the
    /// object's own AddRef -- sl_com_retain is a null test and an indirect call,
    /// in one place rather than emitted at every site.
    /// </summary>
    private static string RetainOf(TypeSymbol type) =>
        type is WeakTypeSymbol ? "sl_weak_retain"
        : IsComReference(type) ? "sl_com_retain"
        : "sl_retain";

    private static string ReleaseOf(TypeSymbol type) =>
        type is WeakTypeSymbol ? "sl_weak_release"
        : IsComReference(type) ? "sl_com_release"
        : "sl_release";

    private void Retain(string value, TypeSymbol type) =>
        Line($"call void @{RetainOf(type)}(ptr {value})");

    private void Release(string value, TypeSymbol type) =>
        Line($"call void @{ReleaseOf(type)}(ptr {value})");
}
