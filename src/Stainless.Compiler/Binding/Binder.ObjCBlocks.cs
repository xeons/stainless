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
/// Objective-C blocks: <c>objc closure</c> types, and the lambdas and
/// closures that become them.
///
/// A block is a closure Objective-C can call. It holds a Stainless closure
/// of the same signature, so a lambda is bound as that closure first and the
/// emitter wraps it.
/// </summary>
public sealed partial class Binder
{
    /// <summary>
    /// The type an <c>objc closure</c> declares, with the closure type of the
    /// same signature it is built from. The closure is named after the block
    /// and kept among the program's structs, since a value of it is made
    /// whenever a lambda becomes the block.
    /// </summary>
    private ObjCBlockTypeSymbol NewBlockType(DelegateDeclSyntax declaration, ModuleSymbol module)
    {
        var closure = NewClosureType(declaration, module, displayName: declaration.Name + "$Closure");
        _structs.Add(closure);

        return new ObjCBlockTypeSymbol
        {
            SimpleName = declaration.Name,
            ModuleName = module.Name,
            IsPublic = declaration.Modifiers.HasFlag(Modifiers.Public),
            Span = declaration.Span,
            Documentation = declaration.Documentation,
            Closure = closure,
        };
    }

    /// <summary>
    /// What a block takes and gives back crosses to Objective-C as a message's
    /// arguments do (SL0907); an <c>out</c> or <c>ref</c> has nothing to be
    /// written back through, so it is a pointer or nothing.
    /// </summary>
    private void CheckBlockSignature(ObjCBlockTypeSymbol block, DelegateDeclSyntax declaration)
    {
        foreach (var parameter in block.Signature)
        {
            if (parameter.Mode is ParameterMode.Out or ParameterMode.Ref)
                diagnostics.Report(Codes.ObjCSignatureCannotCross, declaration.Span,
                    $"'{parameter.Name}' of the block '{block.Name}' is '{(parameter.Mode == ParameterMode.Out ? "out" : "ref")}', " +
                    "and a block's arguments are written back by nothing; declare a pointer",
                    block);
            else if (ObjCSignatureProblem(parameter.Type) is { } why)
                diagnostics.Report(Codes.ObjCSignatureCannotCross, declaration.Span,
                    $"'{parameter.Name}' of the block '{block.Name}' is {why}, which a block " +
                    "cannot carry; it takes what C can spell and Objective-C objects",
                    parameter.Type);
        }

        if (ObjCSignatureProblem(block.ReturnType) is { } result)
            diagnostics.Report(Codes.ObjCSignatureCannotCross, declaration.Span,
                $"the block '{block.Name}' returns {result}, which a block cannot carry; it " +
                "takes what C can spell and Objective-C objects",
                block.ReturnType);
    }

    /// <summary>
    /// A lambda or a method becoming a block, or an optional one: bound as the
    /// block's closure, then made a block of. Null when the target is not a
    /// block.
    /// </summary>
    private BoundExpression? BindAsBlock(BoundExpression expression, TypeSymbol target, SourceSpan span)
    {
        if (expression is not (BoundLambda or BoundFunctionGroup)) return null;

        if (target is OptionalTypeSymbol { Element: ObjCBlockTypeSymbol held })
        {
            var made = BindConversion(expression, held, span);
            return made.Type.IsError()
                ? made
                : new BoundConversion(span, target, made, ConversionKind.ReferenceToOptional);
        }

        if (target is not ObjCBlockTypeSymbol block) return null;

        RequireDarwin(span);
        var closure = BindConversion(expression, block.Closure, span);
        return closure.Type.IsError()
            ? closure
            : new BoundConversion(span, block, closure, ConversionKind.ClosureToBlock);
    }

    /// <summary>True when a closure of <paramref name="closure"/>'s type may become a <paramref name="block"/>.</summary>
    private static bool BecomesBlock(ClosureTypeSymbol closure, ObjCBlockTypeSymbol block) =>
        !closure.IsNullable &&
        closure.ReturnType == block.ReturnType &&
        closure.Signature.Count == block.Signature.Count &&
        closure.Signature.Zip(block.Signature).All(p => p.First.Type == p.Second.Type && p.First.Mode == p.Second.Mode);

    /// <summary>
    /// A call through a block, as through the closure it holds: the arguments
    /// are arranged against its signature, and the emitter calls the block's
    /// invoke function rather than the closure's.
    /// </summary>
    private BoundExpression BuildBlockCall(
        CallSyntax syntax, ObjCBlockTypeSymbol block, BoundExpression target, List<BoundExpression> arguments)
    {
        RequireDarwin(syntax.Span);
        if (ArrangeThroughSignature(syntax, block.Name, block.Closure.SignatureText,
                block.ReturnType, block.Signature, arguments, out var order) is not { } converted)
            return new BoundErrorExpression(syntax.Span);

        return new BoundClosureCall(syntax.Span, block.Closure, target, converted)
            { EvaluationOrder = order };
    }
}
