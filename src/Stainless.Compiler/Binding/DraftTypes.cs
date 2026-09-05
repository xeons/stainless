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
/// The type of a bare case name before something says which variant it builds.
///
/// One value cannot say what a variant's type arguments are -- <c>Ok(4)</c>
/// knows T and nothing about E -- and type arguments cannot be written at a
/// call. So construction is target-typed, exactly as a lambda is, and this is
/// the placeholder that carries the pieces until a conversion resolves it. It
/// never reaches the emitter.
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
