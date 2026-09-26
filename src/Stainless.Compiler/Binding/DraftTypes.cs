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

using Stainless.Source;
using Stainless.Syntax;

namespace Stainless.Binding;

/// <summary>
/// The type of a lambda before something tells it what to be. It never reaches
/// the emitter: a conversion either resolves it or reports an error.
/// </summary>
public sealed class LambdaType : TypeSymbol
{
    public static readonly LambdaType Instance = new();
    private LambdaType() { }
    public override string Name => "lambda";
    public override int Size => 8;
    public override int Alignment => 8;
}

/// <summary>
/// What an array literal is before anything says what it should be. It never
/// reaches the emitter: either a conversion settles it, or the binder settles
/// it from its elements, or it is an error.
/// </summary>
public sealed class ArrayDraftType : TypeSymbol
{
    public static readonly ArrayDraftType Instance = new();
    private ArrayDraftType() { }
    public override string Name => "array literal";
    public override int Size => 8;
    public override int Alignment => 8;
}

/// <summary>
/// What <c>(null, 1)</c> is before anything says what it should be: a tuple
/// with an element that waits to be told its type, and so no tuple type of
/// its own. It never reaches the emitter: a conversion to a tuple type settles
/// it element by element, or it is an error.
/// </summary>
public sealed class TupleDraftType : TypeSymbol
{
    public static readonly TupleDraftType Instance = new();
    private TupleDraftType() { }
    public override string Name => "tuple literal";
    public override int Size => 0;
    public override int Alignment => 1;
}

/// <summary>A tuple written out, one of whose elements has no type yet.</summary>
public sealed class BoundTupleDraft(SourceSpan span, IReadOnlyList<BoundExpression> elements)
    : BoundExpression(span, TupleDraftType.Instance)
{
    public IReadOnlyList<BoundExpression> Elements { get; } = elements;
}

/// <summary>
/// The type of a bare case name before something says which variant it builds.
///
/// One value cannot say what a variant's type arguments are -- <c>Ok(4)</c>
/// knows T and nothing about E. So construction is target-typed, exactly as a
/// lambda is, and this is the placeholder that carries the pieces until a
/// conversion resolves it. It never reaches the emitter.
/// </summary>
public sealed class VariantDraftType : TypeSymbol
{
    public static readonly VariantDraftType Instance = new();
    private VariantDraftType() { }
    public override string Name => "a variant's case";
    public override int Size => 0;
    public override int Alignment => 1;
}

/// <summary>A <c>Case(...)</c> awaiting the variant type it belongs to.</summary>
public sealed class BoundVariantDraft(
    SourceSpan span, string variantCase, IReadOnlyList<BoundExpression> arguments)
    : BoundExpression(span, VariantDraftType.Instance)
{
    public string Case { get; } = variantCase;
    public IReadOnlyList<BoundExpression> Arguments { get; } = arguments;
}

/// <summary>
/// The type of a bare function name before a delegate gives it one. It never
/// reaches the emitter: a conversion either resolves it or reports an error.
/// </summary>
public sealed class FunctionGroupType : TypeSymbol
{
    public static readonly FunctionGroupType Instance = new();
    private FunctionGroupType() { }
    public override string Name => "function";
    public override int Size => 8;
    public override int Alignment => 8;
}

/// <summary>
/// The type of the <c>null</c> literal before it adopts a target type. It never
/// appears in a declaration, only briefly during binding.
/// </summary>
public sealed class NullType : TypeSymbol
{
    public static readonly NullType Instance = new();
    private NullType() { }
    public override string Name => "null";
    public override int Size => 8;
    public override int Alignment => 8;
}

/// <summary>
/// The type of a bare <c>default</c> before something says what it is the
/// zero of. It never reaches the emitter: a conversion settles it into a
/// <see cref="BoundDefault"/> of the target type, or it is an error.
/// </summary>
public sealed class DefaultLiteralType : TypeSymbol
{
    public static readonly DefaultLiteralType Instance = new();
    private DefaultLiteralType() { }
    public override string Name => "default";
    public override int Size => 0;
    public override int Alignment => 1;
}

/// <summary>
/// The type of <c>new(...)</c> before something says what it makes. It never
/// reaches the emitter.
/// </summary>
public sealed class NewDraftType : TypeSymbol
{
    public static readonly NewDraftType Instance = new();
    private NewDraftType() { }
    public override string Name => "new()";
    public override int Size => 0;
    public override int Alignment => 1;
}

/// <summary>
/// A <c>new(...)</c> awaiting its type. The arguments are bound where they
/// were written, so settling it later changes nothing about what they mean.
/// </summary>
public sealed class BoundNewDraft(
    SourceSpan span, NewSyntax syntax, List<BoundExpression> arguments)
    : BoundExpression(span, NewDraftType.Instance)
{
    public NewSyntax Syntax { get; } = syntax;
    public List<BoundExpression> Arguments { get; } = arguments;
}
