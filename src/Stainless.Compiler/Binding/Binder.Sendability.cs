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
/// Whether a value may be reached by more than one thread.
///
/// Small, and separate because it is asked from three unrelated places:
/// a spawn, a static, and a <c>[Shared]</c> field.
/// </summary>
public sealed partial class Binder
{
    // ============================================================ sendability

    /// <summary>
    /// Whether a value of this type may be reached by more than one thread.
    ///
    /// Reference counts are atomic, so sharing an object no longer corrupts its
    /// count. What is left is the harder half: nothing synchronizes the object's
    /// *contents*, and two threads writing the same field is a race no count
    /// could have saved. Three cases are safe:
    ///
    ///   plain data       there is no shared mutable state; a value is copied
    ///   String           immutable, and its bytes live inside the object
    ///   [Shared]         the author has said the type synchronizes internally
    ///
    /// An array of plain data is included as a fourth, and it is the one that is
    /// pragmatic rather than proven: a job borrows the array without retaining
    /// it, which is sound as far as it goes, but nothing yet stops the job from
    /// storing it somewhere and retaining it then. It earns its place because
    /// data parallelism is the point of `parallel for`, and rejecting it would
    /// leave the feature with nothing to iterate.
    /// </summary>
    private bool IsSendable(TypeSymbol type) => type switch
    {
        PrimitiveTypeSymbol or PointerTypeSymbol or EnumTypeSymbol or DelegateTypeSymbol => true,

        // A variant's own fields are a tag and a blob of bytes, both of them
        // plain data, so asking them would say yes to a variant holding a List.
        // What it really holds is whatever its cases hold.
        VariantTypeSymbol variant =>
            variant.Cases.SelectMany(c => c.Fields).All(f => IsSendable(f.Type)),

        // A struct is as safe as the things inside it. Copying one retains what
        // it holds, and that is sound now that counts are atomic, so a struct of
        // primitives and Strings crosses as freely as its parts would.
        StructTypeSymbol structType => structType.Fields.All(f => IsSendable(f.Type)),

        ArrayTypeSymbol array => IsPlainData(array.Element),

        // T[N] is not a reference to anything: it is its elements, laid out
        // where it is written. So it travels exactly as they do, and a struct
        // holding one is no more shared than the fields beside it.
        FixedArrayTypeSymbol inline => IsSendable(inline.Element),

        _ when _builtins.IsString(type) => true,

        NamedTypeSymbol named => IsShared(named),

        OptionalTypeSymbol optional => IsSendable(optional.Element),

        _ => false,
    };

    private bool IsPlainData(TypeSymbol type) =>
        type is PrimitiveTypeSymbol or PointerTypeSymbol or EnumTypeSymbol or DelegateTypeSymbol
        || (type is StructTypeSymbol structType && !structType.CarriesReferences())
        || (type is FixedArrayTypeSymbol inline && IsPlainData(inline.Element));

    /// <summary>True when the type carries <c>[Shared]</c>.</summary>
    private static bool IsShared(NamedTypeSymbol type) =>
        type.Attributes.Any(a => a.Type.SimpleName == "Shared");

    /// <summary>
    /// True for an enum marked <c>[Flags]</c>: a set of bits rather than a
    /// choice among alternatives, and so something <c>|</c> can combine.
    /// </summary>
    private bool IsFlags(TypeSymbol type) =>
        type is EnumTypeSymbol enumType &&
        enumType.Attributes.Any(a => a.Type == _builtins.Flags);

    /// <summary>
    /// Reports a value that would be reachable from two threads at once.
    /// The message names the three ways out, because the fix is never obvious
    /// from the rule alone.
    /// </summary>
    private void ReportNotSendable(TypeSymbol type, SourceSpan span, string what)
    {
        diagnostics.Error("SL0377", span,
            $"{what} is '{type.Name}', which more than one thread would reach, and " +
            "nothing about it says how two of them may. Counts are atomic, so the " +
            "reference itself is safe; what is not is the contents. Pass plain data or " +
            $"a String, guard it with 'Mutex<T>', or mark '{type.Name}' with [Shared] " +
            "if it already synchronizes itself");
    }
}
