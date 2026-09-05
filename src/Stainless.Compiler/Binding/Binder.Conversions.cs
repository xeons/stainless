// Stainless - an experimental systems language.
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

using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// What may become what, implicitly and by a cast.
///
/// Also where the target-typed drafts are settled: a lambda, an array
/// literal, a variant case and a bare function name each become
/// something here or become an error.
/// </summary>
public sealed partial class Binder
{
    // ------------------------------------------------------------ conversions

    private BoundExpression BindConversion(BoundExpression expression, TypeSymbol target, SourceSpan span)
    {
        if (expression.Type.IsError() || target.IsError()) return expression;

        // A string literal may be handed straight to C: its bytes are static and
        // NUL-terminated, so there is no lifetime to get wrong. A String held in
        // a variable is a different matter, and must go through ToPointer().
        if (expression is BoundStringLiteral literal && IsBytePointer(target))
            return new BoundConversion(span, target, literal, ConversionKind.StringLiteralToPointer);

        // A function name becomes a delegate by naming the overload that matches.
        if (expression is BoundFunctionGroup group)
            return BindFunctionReference(group, target, span);

        // A lambda has no type until it is told what to be.
        if (expression is BoundLambda lambda)
            return BindLambda(lambda, target, span);

        // Nor has `Ok(x)`, for the same reason and by the same route.
        if (expression is BoundVariantDraft draft)
            return BindVariantSettle(draft, target, span);

        // Nor `[a, b, c]`.
        if (expression is BoundArrayDraft arrayDraft)
            return BindArraySettle(arrayDraft, target, span);

        // A literal that fits simply adopts the target type; there is nothing to
        // convert at run time.
        if (ConstantFits(expression, target) || CharacterFits(expression, target))
            return new BoundLiteral(span, target, ((BoundLiteral)expression).Value);

        if (_builtins.IsString(expression.Type) && IsBytePointer(target))
        {
            diagnostics.Error("SL0293", span,
                "a String does not convert to 'byte*' on its own; call ToPointer() to hand its " +
                "bytes to C, and keep the String alive for as long as C holds the pointer");
            return new BoundErrorExpression(span);
        }

        var kind = ClassifyConversion(expression.Type, target, explicitCast: false);
        if (kind is null)
        {
            // Between two code unit types the generic message says what
            // happened and not why, and the why is the whole rule.
            if (expression.Type is PrimitiveTypeSymbol { IsCodeUnit: true } fromUnit &&
                target is PrimitiveTypeSymbol { IsCodeUnit: true } toUnit)
            {
                diagnostics.Error("SL0527", span, CodeUnitMessage(expression, fromUnit, toUnit));
                return new BoundErrorExpression(span);
            }

            string hint = ClassifyConversion(expression.Type, target, explicitCast: true) is not null
                ? $"; an explicit cast '({target.Name})' would allow it"
                : "";
            diagnostics.Error("SL0265", span,
                $"cannot convert '{expression.Type.Name}' to '{target.Name}'{hint}");
            return new BoundErrorExpression(span);
        }

        // An identity conversion still has to be recorded when the types differ,
        // as between an enum and its underlying integer: same bits, different type.
        if (kind == ConversionKind.Identity && expression.Type.Equals(target)) return expression;

        // Null adopts the target type rather than being converted at runtime.
        if (expression is BoundNullLiteral) return new BoundNullLiteral(span, target);

        return new BoundConversion(span, target, expression, kind.Value);
    }

    /// <summary>
    /// Resolves a bare function name against the delegate it is being stored in.
    /// Overloads are separated by the signature the delegate asks for, which is
    /// the only context a bare name has.
    /// </summary>
    private BoundExpression BindFunctionReference(
        BoundFunctionGroup group, TypeSymbol target, SourceSpan span)
    {
        if (target is not DelegateTypeSymbol wanted)
        {
            diagnostics.Error("SL0360", span,
                $"'{group.Name}' is a function; it converts to a delegate type, " +
                $"and '{target.Name}' is not one");
            return new BoundErrorExpression(span);
        }

        var matches = group.Candidates.Where(wanted.Accepts).ToList();

        if (matches.Count == 0)
        {
            diagnostics.Error("SL0361", span,
                $"no overload of '{group.Name}' matches delegate '{wanted.Name}', " +
                $"which is '{wanted.SignatureText}'");
            return new BoundErrorExpression(span);
        }

        if (matches.Count > 1)
        {
            diagnostics.Error("SL0362", span,
                $"'{group.Name}' is ambiguous for delegate '{wanted.Name}'");
            return new BoundErrorExpression(span);
        }

        return new BoundFunctionReference(span, wanted, matches[0]);
    }

    /// <summary>
    /// Returns how to get from <paramref name="from"/> to <paramref name="to"/>,
    /// or null when no such conversion exists.
    /// </summary>
    /// <summary>
    /// Whether an integer literal fits the target type exactly, as in C#, where
    /// <c>byte b = 200;</c> and <c>nuint n = 5;</c> need no cast because the
    /// compiler can see the value. Only a literal qualifies: anything computed
    /// still needs an explicit cast.
    /// </summary>
    private static bool ConstantFits(BoundExpression expression, TypeSymbol target)
    {
        if (expression is not BoundLiteral { Value: ulong value }) return false;
        if (expression.Type is not PrimitiveTypeSymbol { IsInteger: true }) return false;
        if (target is not PrimitiveTypeSymbol { IsInteger: true } integer) return false;

        ulong maximum = integer.Size >= 8
            ? (integer.IsSigned ? long.MaxValue : ulong.MaxValue)
            : (1UL << (integer.Bits - (integer.IsSigned ? 1 : 0))) - 1;

        return value <= maximum;
    }

    /// <summary>
    /// Whether a character literal may simply adopt <paramref name="target"/>.
    ///
    /// The literal is a scalar, and each code unit type holds a different range
    /// of them in a single unit: <c>char</c> is one UTF-8 byte and so stops at
    /// U+007F, <c>char16</c> is one UTF-16 unit and so stops below the
    /// surrogates' own range, and <c>char32</c> holds every scalar there is.
    /// Any other integer takes it as the number it is, which is what makes
    /// <c>const int Tab = '	';</c> work.
    /// </summary>
    private static bool CharacterFits(BoundExpression expression, TypeSymbol target)
    {
        if (expression is not BoundLiteral { Value: int scalar }) return false;
        if (expression.Type is not PrimitiveTypeSymbol { IsCodeUnit: true }) return false;
        if (target is not PrimitiveTypeSymbol { IsInteger: true } integer) return false;

        return integer.Kind switch
        {
            PrimitiveKind.Char => scalar < 0x80,
            PrimitiveKind.Char16 => scalar < 0x10000,
            PrimitiveKind.Char32 => true,
            _ => integer.Size >= 4 ||
                 scalar <= (1 << (integer.Bits - (integer.IsSigned ? 1 : 0))) - 1,
        };
    }

    /// <summary>
    /// Why one code unit type will not become another.
    ///
    /// A character literal that does not fit gets the specific answer, because
    /// the scalar is known and the count of units it needs is the argument.
    /// Anything else gets the general one.
    /// </summary>
    private static string CodeUnitMessage(
        BoundExpression expression, PrimitiveTypeSymbol from, PrimitiveTypeSymbol to)
    {
        string wider = to.Kind == PrimitiveKind.Char ? "'char16' or 'char32'" : "'char32'";

        if (expression is BoundLiteral { Value: int scalar })
        {
            int units = to.Kind switch
            {
                PrimitiveKind.Char => Utf8Length(scalar),
                PrimitiveKind.Char16 => scalar >= 0x10000 ? 2 : 1,
                _ => 1,
            };
            string unitName = to.Kind == PrimitiveKind.Char ? "bytes of UTF-8" : "UTF-16 units";

            return $"U+{scalar:X4} takes {units} {unitName}, so it is not one '{to.Name}'; " +
                   $"declare it {wider}";
        }

        return $"'{from.Name}' and '{to.Name}' are different encodings, not different widths " +
               $"of one, so one does not become the other on its own; a cast '({to.Name})' " +
               "moves the bits across and re-encodes nothing";
    }

    private static int Utf8Length(int scalar) =>
        scalar < 0x80 ? 1 : scalar < 0x800 ? 2 : scalar < 0x10000 ? 3 : 4;

    /// <summary>True for <c>byte*</c>, the shape C expects for text.</summary>
    private static bool IsBytePointer(TypeSymbol type) =>
        type is PointerTypeSymbol { Element: PrimitiveTypeSymbol { Kind: PrimitiveKind.Byte } };

    private ConversionKind? ClassifyConversion(TypeSymbol from, TypeSymbol to, bool explicitCast)
    {
        if (from.Equals(to)) return ConversionKind.Identity;

        // null literal -> any nullable representation. A delegate is a raw
        // function pointer, so a null one is exactly C's null callback.
        if (from is NullType)
            return to is PointerTypeSymbol or OptionalTypeSymbol or WeakTypeSymbol or DelegateTypeSymbol
                ? ConversionKind.NullToReference
                : null;

        // The whole of an array, as a slice of it.
        if (from is ArrayTypeSymbol whole && to is SliceTypeSymbol asSlice)
            return whole.Element.Equals(asSlice.Element) ? ConversionKind.ArrayToSlice : null;

        // A derived class is a base class. With single inheritance the base
        // subobject starts where the object does, so this is the same pointer
        // and emits nothing; the other direction is a check.
        if (from is ClassTypeSymbol fromDerived && to is ClassTypeSymbol toBase)
        {
            if (fromDerived.DerivesFrom(toBase)) return ConversionKind.Upcast;
            return explicitCast && toBase.DerivesFrom(fromDerived)
                ? ConversionKind.Downcast
                : null;
        }

        // A pointer COM wrote through a void**, taken into ARC's care. The
        // other direction is an ordinary pointer cast, and byte* is the
        // language's void*, so it needs no rule of its own.
        if (from is PointerTypeSymbol && to is ComInterfaceTypeSymbol)
            return explicitCast ? ConversionKind.ComAdopt : null;

        if (from is ComInterfaceTypeSymbol && to is PointerTypeSymbol)
            return explicitCast || IsBytePointer(to) ? ConversionKind.PointerCast : null;

        // Between com interfaces the vtable is the prefix rather than the
        // object, so a derived reference already satisfies the base and the
        // other direction is a QueryInterface.
        if (from is ComInterfaceTypeSymbol fromCom && to is ComInterfaceTypeSymbol toCom)
        {
            if (fromCom.DerivesFrom(toCom)) return ConversionKind.ComUpcast;
            return explicitCast ? ConversionKind.ComQuery : null;
        }

        // A com class, as one of the interfaces it presents. Not free: what the
        // caller gets is the tear-off's address, which is inside the object.
        if (from is ClassTypeSymbol { IsCom: true } presenting &&
            to is ComInterfaceTypeSymbol presented)
            return presenting.ComInterfaces.Contains(presented) ||
                   presented == _builtins.Unknown
                ? ConversionKind.ComTearOff
                : null;

        // A class converts to any interface it implements, and an interface to
        // any it extends. Because a reference is the same pointer either way,
        // this costs nothing at run time.
        if (from is NamedTypeSymbol { IsReferenceType: true } source2 && to is InterfaceTypeSymbol wanted)
            return source2.AllInterfaces().Contains(wanted) ? ConversionKind.ClassToInterface : null;

        if (from is ClassTypeSymbol optionalImplementer &&
            to is OptionalTypeSymbol { Element: InterfaceTypeSymbol optionalWanted })
            return optionalImplementer.Interfaces.Contains(optionalWanted)
                ? ConversionKind.ClassToInterface
                : null;

        // C -> C?  and  weak C? -> C? are reference identities at runtime, and
        // so is Derived -> Base?, which is both conversions at once and neither
        // of them any instructions.
        if (from is ClassTypeSymbol fromClass && to is OptionalTypeSymbol toOptional)
            return toOptional.Element is ClassTypeSymbol optionalBase && fromClass.DerivesFrom(optionalBase)
                ? ConversionKind.ReferenceToOptional
                : null;

        // Derived? -> Base?, for the same reason.
        if (from is OptionalTypeSymbol { Element: ClassTypeSymbol optionalDerived } &&
            to is OptionalTypeSymbol { Element: ClassTypeSymbol optionalWantedBase } &&
            optionalDerived.DerivesFrom(optionalWantedBase))
            return ConversionKind.Upcast;

        if (from is InterfaceTypeSymbol fromInterface && to is OptionalTypeSymbol toOptionalInterface)
            return fromInterface.Equals(toOptionalInterface.Element)
                ? ConversionKind.ReferenceToOptional
                : null;

        // I -> I?, and IDerived -> IBase?, both of which are the same pointer.
        if (from is ComInterfaceTypeSymbol fromComReference &&
            to is OptionalTypeSymbol { Element: ComInterfaceTypeSymbol wantedCom } &&
            fromComReference.DerivesFrom(wantedCom))
            return ConversionKind.ReferenceToOptional;

        // A com class straight to an optional interface, which is the two
        // conversions above at once and still one add.
        if (from is ClassTypeSymbol { IsCom: true } presentingOptional &&
            to is OptionalTypeSymbol { Element: ComInterfaceTypeSymbol optionalPresented } &&
            (presentingOptional.ComInterfaces.Contains(optionalPresented) ||
             optionalPresented == _builtins.Unknown))
            return ConversionKind.ComTearOff;

        if (from is WeakTypeSymbol fromWeak && to is OptionalTypeSymbol weakTarget)
            return fromWeak.Element.Equals(weakTarget.Element) ? ConversionKind.ReferenceToOptional : null;

        // C -> weak C?  and  C? -> weak C?. This is the only way to break a
        // reference cycle, since ARC cannot collect one, so it is implicit: the
        // weak slot already says what is meant, and requiring a cast as well
        // would put punctuation between the programmer and the one escape hatch
        // they have.
        if (to is WeakTypeSymbol toWeak)
        {
            var referenced = from is OptionalTypeSymbol weakSource ? weakSource.Element : from;
            return referenced is NamedTypeSymbol { IsReferenceType: true } &&
                   referenced.Equals(toWeak.Element)
                ? ConversionKind.ReferenceToWeak
                : null;
        }

        // C? -> C discards a null check, so it must be explicit.
        if (from is OptionalTypeSymbol fromOptional && to is NamedTypeSymbol { IsReferenceType: true })
        {
            if (!explicitCast) return null;
            if (fromOptional.Element.Equals(to)) return ConversionKind.PointerCast;

            // Derived? -> Base loses the null and nothing else; Base? -> Derived
            // loses the null and checks what is left.
            return fromOptional.Element is ClassTypeSymbol optionalSource && to is ClassTypeSymbol castTarget
                ? optionalSource.DerivesFrom(castTarget) ? ConversionKind.PointerCast
                  : castTarget.DerivesFrom(optionalSource) ? ConversionKind.Downcast
                  : null
                : null;
        }

        if (from is PointerTypeSymbol && to is PointerTypeSymbol)
        {
            // Any pointer converts to byte* implicitly, mirroring C's void*.
            bool toBytePointer = to is PointerTypeSymbol { Element: PrimitiveTypeSymbol { Kind: PrimitiveKind.Byte } };
            return explicitCast || toBytePointer ? ConversionKind.PointerCast : null;
        }

        // A reference to a raw pointer, explicitly. Reflection needs it to read an
        // instance by field offset; the result is uncounted, so keep the
        // reference alive for as long as the pointer is used.
        if (from is NamedTypeSymbol { IsReferenceType: true } or ArrayTypeSymbol &&
            to is PointerTypeSymbol)
            return explicitCast ? ConversionKind.PointerCast : null;

        // And back again, which is what lets a C callback recover the object it
        // was given as context. Nothing checks that the pointer really points at
        // one of these, so the cast is an assertion by the programmer -- the same
        // bargain the other direction already makes.
        if (from is PointerTypeSymbol &&
            to is NamedTypeSymbol { IsReferenceType: true } or ArrayTypeSymbol)
            return explicitCast ? ConversionKind.PointerCast : null;

        if (from is PointerTypeSymbol && to is PrimitiveTypeSymbol { IsInteger: true, Size: 8 })
            return explicitCast ? ConversionKind.PointerToInteger : null;

        if (from is PrimitiveTypeSymbol { IsInteger: true, Size: 8 } && to is PointerTypeSymbol)
            return explicitCast ? ConversionKind.IntegerToPointer : null;

        // An enum never converts implicitly, in either direction. That is the
        // whole point of declaring one: a Level is not a byte that happens to be
        // small, and a byte is not a Level. An explicit cast is still available,
        // which is what interop and serialization need.
        if (from is EnumTypeSymbol || to is EnumTypeSymbol)
        {
            if (!explicitCast) return null;

            var fromCore = from is EnumTypeSymbol fromEnum ? fromEnum.UnderlyingType : from;
            var toCore = to is EnumTypeSymbol toEnum ? toEnum.UnderlyingType : to;

            if (fromCore is not PrimitiveTypeSymbol { IsInteger: true } ||
                toCore is not PrimitiveTypeSymbol { IsInteger: true })
                return null;

            return ClassifyConversion(fromCore, toCore, explicitCast: true);
        }

        if (from is not PrimitiveTypeSymbol source || to is not PrimitiveTypeSymbol target) return null;
        if (source.Kind == PrimitiveKind.Void || target.Kind == PrimitiveKind.Void) return null;

        if (source.Kind == PrimitiveKind.Bool)
            return target.IsInteger && explicitCast ? ConversionKind.BoolToInteger : null;
        if (target.Kind == PrimitiveKind.Bool) return null;

        if (source.IsFloat && target.IsFloat)
            return target.Size >= source.Size || explicitCast ? ConversionKind.FloatResize : null;

        if (source.IsInteger && target.IsFloat)
            return ConversionKind.IntToFloat;               // implicit, as in C#

        if (source.IsFloat && target.IsInteger)
            return explicitCast ? ConversionKind.FloatToInt : null;

        // char, char16 and char32 are three encodings, not three widths of one
        // type. 'e' is one byte of UTF-8, one UTF-16 unit and one scalar; 'e'
        // with an acute accent is two, one and one; an emoji is four, two and
        // one. So widening one to another re-encodes nothing and produces a
        // unit that means something else, which is a bug a cast should have to
        // spell. Against every other integer they behave as integers.
        if (source.IsCodeUnit && target.IsCodeUnit && source.Kind != target.Kind && !explicitCast)
            return null;

        if (source.IsInteger && target.IsInteger)
        {
            if (target.Size > source.Size && (source.IsSigned == target.IsSigned || !source.IsSigned))
                return ConversionKind.IntegerWiden;
            if (target.Size == source.Size && source.IsSigned == target.IsSigned)
                return ConversionKind.Identity;
            if (!explicitCast) return null;
            return target.Size >= source.Size ? ConversionKind.IntegerWiden : ConversionKind.IntegerNarrow;
        }

        return null;
    }
}
